import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import endpointHandler from "../extract-recipe.mjs";
import { createExtractRecipeHandler } from "./extract-recipe-handler.mjs";
import { recipeDraftSchema, validateRecipeDraft } from "./recipe-draft-schema.mjs";

const allowedOrigin = "https://championship.example";
const validEnvironment = Object.freeze({
  OPENAI_API_KEY: "test-api-key",
  OPENAI_MODEL: "test-extraction-model",
  ALLOWED_ORIGIN: allowedOrigin,
});

const sampleDraft = JSON.parse(
  await readFile(
    new URL("../../assets/championship/sample_croissant_draft.json", import.meta.url),
    "utf8"
  )
);

test("exports the configured endpoint handler", () => {
  assert.equal(typeof endpointHandler, "function");
});

function liveDraft(sourceKind = "text") {
  const draft = structuredClone(sampleDraft);
  draft.sourceKind = sourceKind;
  return draft;
}

function providerResponse(draft = liveDraft(), init = {}) {
  const body = {
    status: "completed",
    output: [
      {
        type: "message",
        role: "assistant",
        status: "completed",
        content: [
          {
            type: "output_text",
            text: JSON.stringify(draft),
            annotations: [],
          },
        ],
      },
    ],
  };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
    ...init,
  });
}

function requestFor(body, overrides = {}) {
  const { headers = {}, ...requestOverrides } = overrides;
  return {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: allowedOrigin,
      ...headers,
    },
    body,
    ...requestOverrides,
  };
}

function textRequest(text = "Recipe name: Croissant dough", overrides = {}) {
  return requestFor(
    {
      sourceKind: "text",
      text,
      imageDataUrl: null,
      locale: "en",
    },
    overrides
  );
}

function imageRequest(imageDataUrl = "data:image/png;base64,AQID", overrides = {}) {
  return requestFor(
    {
      sourceKind: "image",
      text: null,
      imageDataUrl,
      locale: "ko",
    },
    overrides
  );
}

function createResponseRecorder() {
  const headers = new Map();
  return {
    statusCode: 200,
    body: "",
    headers,
    setHeader(name, value) {
      headers.set(name.toLowerCase(), String(value));
    },
    end(value = "") {
      this.body = String(value);
    },
  };
}

async function invoke({
  request = textRequest(),
  providerFetch = async () => providerResponse(),
  environment = validEnvironment,
  logger = { info() {} },
  timeoutMs = 25_000,
} = {}) {
  const response = createResponseRecorder();
  const handler = createExtractRecipeHandler({
    providerFetch,
    environment,
    logger,
    timeoutMs,
  });
  await handler(request, response);
  return response;
}

function responseJson(response) {
  return JSON.parse(response.body);
}

function assertError(response, status, code) {
  assert.equal(response.statusCode, status);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(Object.keys(responseJson(response)), ["error"]);
  assert.deepEqual(Object.keys(responseJson(response).error), ["code", "message"]);
  assert.equal(responseJson(response).error.code, code);
  assert.equal(typeof responseJson(response).error.message, "string");
}

test("exports a recursively closed strict recipe draft schema", () => {
  const objects = [];
  const visit = (value) => {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (value === null || typeof value !== "object") return;
    if (value.type === "object") objects.push(value);
    Object.values(value).forEach(visit);
  };
  visit(recipeDraftSchema);

  assert.ok(objects.length > 5);
  for (const object of objects) {
    assert.equal(object.additionalProperties, false);
    assert.deepEqual(new Set(object.required), new Set(Object.keys(object.properties)));
  }
  assert.deepEqual(recipeDraftSchema.properties.sourceKind.enum, ["text", "image"]);
});

test("rejects non-POST methods without provider access", async () => {
  let providerCalls = 0;
  const response = await invoke({
    request: requestFor(null, { method: "GET" }),
    providerFetch: async () => {
      providerCalls += 1;
      return providerResponse();
    },
  });

  assertError(response, 405, "method_not_allowed");
  assert.equal(response.headers.get("allow"), "POST");
  assert.equal(providerCalls, 0);
});

test("rejects a non-JSON content type and always disables caching", async () => {
  const response = await invoke({
    request: textRequest("private source", {
      headers: { "content-type": "text/plain" },
    }),
  });

  assertError(response, 415, "invalid_content_type");
});

test("accepts application/json with a charset", async () => {
  const response = await invoke({
    request: textRequest("Recipe", {
      headers: { "content-type": "application/json; charset=utf-8" },
    }),
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
});

test("rejects malformed JSON and extra request properties", async (context) => {
  await context.test("malformed JSON", async () => {
    const response = await invoke({ request: requestFor("{") });
    assertError(response, 400, "invalid_request");
  });

  await context.test("malformed parsed-body getter", async () => {
    const request = textRequest();
    Object.defineProperty(request, "body", {
      get() {
        throw new SyntaxError("malformed JSON");
      },
    });
    const response = await invoke({ request });
    assertError(response, 400, "invalid_request");
  });

  await context.test("extra property", async () => {
    const body = structuredClone(textRequest().body);
    body.provider = "not-allowed";
    const response = await invoke({ request: requestFor(body) });
    assertError(response, 400, "invalid_request");
  });

  await context.test("missing property", async () => {
    const body = structuredClone(textRequest().body);
    delete body.imageDataUrl;
    const response = await invoke({ request: requestFor(body) });
    assertError(response, 400, "invalid_request");
  });
});

test("rejects invalid text sources before provider access", async (context) => {
  for (const [name, text, code, status] of [
    ["empty", " \n\t ", "invalid_request", 400],
    ["over the scalar limit", "😀".repeat(20_001), "source_too_large", 413],
  ]) {
    await context.test(name, async () => {
      let providerCalls = 0;
      const response = await invoke({
        request: textRequest(text),
        providerFetch: async () => {
          providerCalls += 1;
          return providerResponse();
        },
      });
      assertError(response, status, code);
      assert.equal(providerCalls, 0);
    });
  }
});

test("counts text in Unicode scalar values", async () => {
  let providerCalls = 0;
  const response = await invoke({
    request: textRequest("😀".repeat(20_000)),
    providerFetch: async () => {
      providerCalls += 1;
      return providerResponse();
    },
  });

  assert.equal(response.statusCode, 200);
  assert.equal(providerCalls, 1);
});

test("rejects invalid image sources before provider access", async (context) => {
  const overLimitData = Buffer.alloc(3 * 1024 * 1024 + 1).toString("base64");
  for (const [name, imageDataUrl, code, status] of [
    ["unsupported MIME type", "data:image/gif;base64,AQID", "unsupported_source", 400],
    ["unanchored data URL", "xdata:image/png;base64,AQID", "invalid_request", 400],
    ["malformed base64", "data:image/png;base64,A===", "invalid_request", 400],
    ["non-canonical base64", "data:image/png;base64,AB==", "invalid_request", 400],
    [
      "decoded image over the limit",
      `data:image/webp;base64,${overLimitData}`,
      "source_too_large",
      413,
    ],
  ]) {
    await context.test(name, async () => {
      let providerCalls = 0;
      const response = await invoke({
        request: imageRequest(imageDataUrl),
        providerFetch: async () => {
          providerCalls += 1;
          return providerResponse(liveDraft("image"));
        },
      });
      assertError(response, status, code);
      assert.equal(providerCalls, 0);
    });
  }
});

test("keeps a maximum-size image request below the Vercel payload limit", async () => {
  const payload = Buffer.alloc(3 * 1024 * 1024).toString("base64");
  const request = imageRequest(`data:image/png;base64,${payload}`);
  let providerCalls = 0;
  const response = await invoke({
    request,
    providerFetch: async () => {
      providerCalls += 1;
      return providerResponse(liveDraft("image"));
    },
  });

  assert.ok(Buffer.byteLength(JSON.stringify(request.body)) < 4_500_000);
  assert.equal(response.statusCode, 200);
  assert.equal(providerCalls, 1);
});

test("rejects invalid request variants", async (context) => {
  const cases = [
    [
      "unsupported source kind",
      { ...textRequest().body, sourceKind: "sample" },
      "unsupported_source",
    ],
    ["invalid locale", { ...textRequest().body, locale: "fr" }, "invalid_request"],
    [
      "text request with image",
      { ...textRequest().body, imageDataUrl: "data:image/png;base64,AQID" },
      "invalid_request",
    ],
    ["image request with text", { ...imageRequest().body, text: "recipe" }, "invalid_request"],
  ];
  for (const [name, body, code] of cases) {
    await context.test(name, async () => {
      const response = await invoke({ request: requestFor(body) });
      assertError(response, 400, code);
    });
  }
});

test("requires server configuration and an exact origin match", async (context) => {
  await context.test("missing API key", async () => {
    const response = await invoke({
      environment: { ...validEnvironment, OPENAI_API_KEY: "" },
    });
    assertError(response, 503, "service_unconfigured");
  });

  await context.test("blank API key", async () => {
    const response = await invoke({
      environment: { ...validEnvironment, OPENAI_API_KEY: "   " },
    });
    assertError(response, 503, "service_unconfigured");
  });

  await context.test("missing allowed origin", async () => {
    const response = await invoke({
      environment: { ...validEnvironment, ALLOWED_ORIGIN: "" },
    });
    assertError(response, 503, "service_unconfigured");
  });

  await context.test("origin mismatch", async () => {
    const response = await invoke({
      request: textRequest("Recipe", { headers: { origin: "https://attacker.example" } }),
    });
    assertError(response, 400, "invalid_request");
  });
});

test("sends a bounded text request to the Responses API", async () => {
  let providerUrl;
  let providerInit;
  const response = await invoke({
    request: textRequest("PRIVATE SOURCE"),
    providerFetch: async (url, init) => {
      providerUrl = url;
      providerInit = init;
      return providerResponse();
    },
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(responseJson(response), liveDraft());
  assert.equal(providerUrl, "https://api.openai.com/v1/responses");
  assert.equal(providerInit.method, "POST");
  assert.equal(providerInit.headers.authorization, "Bearer test-api-key");
  assert.equal(providerInit.headers["content-type"], "application/json");
  assert.ok(providerInit.signal instanceof AbortSignal);

  const body = JSON.parse(providerInit.body);
  assert.equal(body.model, "test-extraction-model");
  assert.equal(body.store, false);
  assert.equal(body.background, false);
  assert.equal(body.stream, false);
  assert.deepEqual(body.reasoning, { effort: "low" });
  assert.deepEqual(body.tools, []);
  assert.equal(body.max_output_tokens, 8_192);
  assert.equal("files" in body, false);
  assert.deepEqual(body.text, {
    format: {
      type: "json_schema",
      name: "recipe_draft",
      strict: true,
      schema: recipeDraftSchema,
    },
  });
  assert.match(body.instructions, /Use null instead of guessing\./);
  for (const instruction of [
    /Copy concise source evidence/,
    /Report ambiguity and missing information/,
    /Do not calculate a production target/,
    /scale quantities/,
    /convert units/,
    /infer density/,
    /search/,
    /generate a new recipe/,
    /Do not mark any value as operator-confirmed/,
  ]) {
    assert.match(body.instructions, instruction);
  }
  assert.deepEqual(body.input, [
    {
      role: "user",
      content: [{ type: "input_text", text: "PRIVATE SOURCE" }],
    },
  ]);
});

test("uses the default model and sends one high-detail image", async () => {
  let providerBody;
  const imageDataUrl = "data:image/jpeg;base64,AQID";
  const response = await invoke({
    request: imageRequest(imageDataUrl),
    environment: { ...validEnvironment, OPENAI_MODEL: "" },
    providerFetch: async (_url, init) => {
      providerBody = JSON.parse(init.body);
      return providerResponse(liveDraft("image"));
    },
  });

  assert.equal(response.statusCode, 200);
  assert.equal(providerBody.model, "gpt-5.6-luna");
  assert.deepEqual(providerBody.input, [
    {
      role: "user",
      content: [{ type: "input_image", image_url: imageDataUrl, detail: "high" }],
    },
  ]);
});

test("aborts provider access at the injected timeout", async () => {
  let observedSignal;
  const response = await invoke({
    timeoutMs: 1,
    providerFetch: async (_url, init) => {
      observedSignal = init.signal;
      await new Promise((_resolve, reject) => {
        init.signal.addEventListener("abort", () => reject(init.signal.reason));
      });
    },
  });

  assert.equal(observedSignal.aborted, true);
  assertError(response, 504, "service_timeout");
});

test("keeps the timeout active while consuming the provider body", async () => {
  let observedSignal;
  const response = await invoke({
    timeoutMs: 1,
    providerFetch: async (_url, init) => {
      observedSignal = init.signal;
      return {
        status: 200,
        ok: true,
        async json() {
          await new Promise(() => {});
        },
      };
    },
  });

  assert.equal(observedSignal.aborted, true);
  assertError(response, 504, "service_timeout");
});

test("maps provider failures to stable public errors", async (context) => {
  await context.test("rate limit", async () => {
    const response = await invoke({
      providerFetch: async () => new Response("provider detail", { status: 429 }),
    });
    assertError(response, 503, "service_busy");
  });

  await context.test("provider failure", async () => {
    const response = await invoke({
      providerFetch: async () => new Response("provider detail", { status: 500 }),
    });
    assertError(response, 502, "service_failure");
    assert.doesNotMatch(response.body, /provider detail/);
  });

  await context.test("unexpected fetch exception", async () => {
    const response = await invoke({
      providerFetch: async () => {
        throw new Error("provider secret detail");
      },
    });
    assertError(response, 502, "service_failure");
    assert.doesNotMatch(response.body, /provider secret detail/);
  });
});

test("parses only completed output_text message content", async (context) => {
  await context.test("rejects a top-level convenience field", async () => {
    const response = await invoke({
      providerFetch: async () =>
        new Response(
          JSON.stringify({ status: "completed", output_text: JSON.stringify(liveDraft()) }),
          { status: 200 }
        ),
    });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("rejects malformed JSON output", async () => {
    const response = await invoke({
      providerFetch: async () =>
        new Response(
          JSON.stringify({
            status: "completed",
            output: [
              {
                type: "message",
                role: "assistant",
                status: "completed",
                content: [{ type: "output_text", text: "{" }],
              },
            ],
          }),
          { status: 200 }
        ),
    });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("rejects incomplete responses", async () => {
    const response = await invoke({
      providerFetch: async () =>
        new Response(JSON.stringify({ status: "incomplete", output: [] }), { status: 200 }),
    });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("rejects refusal content", async () => {
    const response = await invoke({
      providerFetch: async () =>
        new Response(
          JSON.stringify({
            status: "completed",
            output: [
              {
                type: "message",
                role: "assistant",
                status: "completed",
                content: [{ type: "refusal", refusal: "cannot comply" }],
              },
            ],
          }),
          { status: 200 }
        ),
    });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("rejects a non-JSON provider response", async () => {
    const response = await invoke({
      providerFetch: async () => new Response("not JSON", { status: 200 }),
    });
    assertError(response, 502, "invalid_model_output");
  });
});

test("revalidates the provider draft before returning it", async (context) => {
  await context.test("extra property", async () => {
    const draft = liveDraft();
    draft.providerId = "not-allowed";
    const response = await invoke({ providerFetch: async () => providerResponse(draft) });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("source kind mismatch", async () => {
    const response = await invoke({
      providerFetch: async () => providerResponse(liveDraft("image")),
    });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("manual quantity", async () => {
    const draft = liveDraft();
    draft.components.at(-1).amount.value = "1";
    const response = await invoke({ providerFetch: async () => providerResponse(draft) });
    assertError(response, 502, "invalid_model_output");
  });

  for (const amount of ["one tablespoon", ""]) {
    await context.test(`non-decimal quantity ${JSON.stringify(amount)}`, async () => {
      const draft = liveDraft();
      draft.components[0].amount.value = amount;
      const response = await invoke({ providerFetch: async () => providerResponse(draft) });
      assertError(response, 502, "invalid_model_output");
    });
  }

  await context.test("blank extracted text", async () => {
    const draft = liveDraft();
    draft.recipe.name.value = "   ";
    const response = await invoke({ providerFetch: async () => providerResponse(draft) });
    assertError(response, 502, "invalid_model_output");
  });

  await context.test("missing evidence for a proposal", async () => {
    const draft = liveDraft();
    draft.recipe.name.evidence = "";
    const response = await invoke({ providerFetch: async () => providerResponse(draft) });
    assertError(response, 502, "invalid_model_output");
  });
});

test("validates live recipe drafts without accepting sample output", () => {
  assert.equal(validateRecipeDraft(liveDraft(), { sourceKind: "text" }), true);
  assert.equal(validateRecipeDraft(sampleDraft, { sourceKind: "text" }), false);
});

test("logs only request metadata and never source or provider content", async () => {
  const logs = [];
  const logger = {
    info(entry) {
      logs.push(entry);
    },
  };
  const textResponse = await invoke({
    request: textRequest("PRIVATE_RECIPE_SOURCE"),
    logger,
    providerFetch: async () => new Response("PRIVATE_PROVIDER_OUTPUT", { status: 500 }),
  });
  const imageResponse = await invoke({
    request: imageRequest("data:image/png;base64,AQID"),
    logger,
    providerFetch: async () => new Response("image provider failure", { status: 500 }),
  });
  const invalidDraft = liveDraft();
  invalidDraft.providerId = "private-provider-id";
  const outputResponse = await invoke({
    logger,
    providerFetch: async () => providerResponse(invalidDraft),
  });

  assertError(textResponse, 502, "service_failure");
  assertError(imageResponse, 502, "service_failure");
  assertError(outputResponse, 502, "invalid_model_output");
  assert.equal(logs.length, 3);
  assert.deepEqual(Object.keys(logs[0]).sort(), [
    "errorCategory",
    "latencyMs",
    "requestId",
    "status",
  ]);
  const serializedLogs = JSON.stringify(logs);
  for (const privateValue of [
    "PRIVATE_RECIPE_SOURCE",
    "PRIVATE_PROVIDER_OUTPUT",
    "private-provider-id",
    "Flour",
    "Butter",
    "data:image",
  ]) {
    assert.doesNotMatch(serializedLogs, new RegExp(privateValue));
  }
});
