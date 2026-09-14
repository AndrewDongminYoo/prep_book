import { randomUUID } from "node:crypto";

import { recipeDraftSchema, validateRecipeDraft } from "./recipe-draft-schema.mjs";

const responsesUrl = "https://api.openai.com/v1/responses";
const defaultModel = "gpt-5.6-luna";
const defaultTimeoutMs = 25_000;
const maxTextScalars = 20_000;
const maxDecodedImageBytes = 3 * 1024 * 1024;
const maxEncodedImageCharacters = 4 * Math.ceil(maxDecodedImageBytes / 3);
const maxOutputTokens = 8_192;
const requestKeys = ["sourceKind", "text", "imageDataUrl", "locale"];
const supportedImageTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

const errorDefinitions = Object.freeze({
  method_not_allowed: [405, "Only POST requests are supported."],
  invalid_content_type: [415, "Content-Type must be application/json."],
  invalid_request: [400, "The request is invalid."],
  unsupported_source: [400, "The source type is not supported."],
  source_too_large: [413, "The submitted source is too large."],
  service_unconfigured: [503, "The extraction service is not configured."],
  service_busy: [503, "The extraction service is busy. Try again."],
  service_timeout: [504, "The extraction service timed out. Try again."],
  invalid_model_output: [502, "The extraction result was invalid. Try again."],
  service_failure: [502, "The extraction service failed. Try again."],
});

export function createExtractRecipeHandler({
  providerFetch = globalThis.fetch,
  environment = process.env,
  logger = console,
  timeoutMs = defaultTimeoutMs,
} = {}) {
  return async function extractRecipeHandler(request, response) {
    const startedAt = Date.now();
    const requestId = randomUUID();
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Content-Type", "application/json; charset=utf-8");

    const finish = (status, errorCategory, body) => {
      try {
        logger.info({
          requestId,
          status,
          latencyMs: Math.max(0, Date.now() - startedAt),
          errorCategory,
        });
      } catch {
        // Logging must not affect the public response.
      }
      response.statusCode = status;
      response.end(JSON.stringify(body));
    };

    const fail = (code) => {
      const [status, message] = errorDefinitions[code];
      finish(status, code, { error: { code, message } });
    };

    try {
      if (request.method !== "POST") {
        response.setHeader("Allow", "POST");
        fail("method_not_allowed");
        return;
      }

      if (!isJsonContentType(readHeader(request.headers, "content-type"))) {
        fail("invalid_content_type");
        return;
      }

      let requestBody;
      try {
        requestBody = request.body;
      } catch {
        fail("invalid_request");
        return;
      }
      const body = parseRequestBody(requestBody);
      if (body === null || !hasExactKeys(body, requestKeys)) {
        fail("invalid_request");
        return;
      }

      const validation = validateSource(body);
      if (!validation.ok) {
        fail(validation.errorCode);
        return;
      }

      const apiKey = environment.OPENAI_API_KEY;
      const allowedOrigin = environment.ALLOWED_ORIGIN;
      if (!isNonBlankString(apiKey) || !isNonBlankString(allowedOrigin)) {
        fail("service_unconfigured");
        return;
      }
      if (readHeader(request.headers, "origin") !== allowedOrigin) {
        fail("invalid_request");
        return;
      }

      const model = isNonBlankString(environment.OPENAI_MODEL)
        ? environment.OPENAI_MODEL
        : defaultModel;
      const controller = new AbortController();
      let timeoutHandle;
      const deadline = new Promise((_resolve, reject) => {
        timeoutHandle = setTimeout(() => {
          controller.abort();
          reject(new Error("provider_timeout"));
        }, timeoutMs);
      });
      let providerResponse;
      let providerBody;
      try {
        providerResponse = await Promise.race([
          providerFetch(responsesUrl, {
            method: "POST",
            headers: {
              authorization: `Bearer ${apiKey}`,
              "content-type": "application/json",
            },
            body: JSON.stringify(buildProviderRequest({ body, model, source: validation.source })),
            signal: controller.signal,
          }),
          deadline,
        ]);
        if (providerResponse.status === 429) {
          fail("service_busy");
          return;
        }
        if (!providerResponse.ok) {
          fail("service_failure");
          return;
        }
        try {
          providerBody = await Promise.race([providerResponse.json(), deadline]);
        } catch {
          fail(controller.signal.aborted ? "service_timeout" : "invalid_model_output");
          return;
        }
      } catch {
        fail(controller.signal.aborted ? "service_timeout" : "service_failure");
        return;
      } finally {
        clearTimeout(timeoutHandle);
      }
      const outputText = extractOutputText(providerBody);
      if (outputText === null) {
        fail("invalid_model_output");
        return;
      }

      let draft;
      try {
        draft = JSON.parse(outputText);
      } catch {
        fail("invalid_model_output");
        return;
      }
      if (!validateRecipeDraft(draft, { sourceKind: body.sourceKind })) {
        fail("invalid_model_output");
        return;
      }

      finish(200, null, draft);
    } catch {
      fail("service_failure");
    }
  };
}

function validateSource(body) {
  if (!["ko", "en"].includes(body.locale)) {
    return { ok: false, errorCode: "invalid_request" };
  }
  if (body.sourceKind === "text") {
    if (
      typeof body.text !== "string" ||
      body.text.trim().length === 0 ||
      body.imageDataUrl !== null
    ) {
      return { ok: false, errorCode: "invalid_request" };
    }
    if (body.text.length > maxTextScalars * 2 || [...body.text].length > maxTextScalars) {
      return { ok: false, errorCode: "source_too_large" };
    }
    return { ok: true, source: body.text };
  }
  if (body.sourceKind !== "image") {
    return { ok: false, errorCode: "unsupported_source" };
  }
  if (body.text !== null || typeof body.imageDataUrl !== "string") {
    return { ok: false, errorCode: "invalid_request" };
  }

  const dataUrl = parseImageDataUrl(body.imageDataUrl);
  if (dataUrl === null) {
    return { ok: false, errorCode: "invalid_request" };
  }
  const { mimeType, payload } = dataUrl;
  if (!supportedImageTypes.has(mimeType)) {
    return { ok: false, errorCode: "unsupported_source" };
  }
  if (payload.length > maxEncodedImageCharacters) {
    return { ok: false, errorCode: "source_too_large" };
  }
  if (!isCanonicalBase64(payload)) {
    return { ok: false, errorCode: "invalid_request" };
  }
  const decodedImage = Buffer.from(payload, "base64");
  if (decodedImage.toString("base64") !== payload) {
    return { ok: false, errorCode: "invalid_request" };
  }
  if (decodedImage.byteLength > maxDecodedImageBytes) {
    return { ok: false, errorCode: "source_too_large" };
  }
  return { ok: true, source: body.imageDataUrl };
}

function buildProviderRequest({ body, model, source }) {
  const localeName = body.locale === "ko" ? "Korean" : "English";
  return {
    model,
    instructions: [
      "Extract only values that the submitted recipe source supports.",
      "Use null instead of guessing.",
      "Copy concise source evidence for every proposed value.",
      "Report ambiguity and missing information in the issues array.",
      "Do not calculate a production target, scale quantities, convert units, infer density, search, or generate a new recipe.",
      "Do not mark any value as operator-confirmed.",
      `Write issue descriptions in ${localeName}.`,
    ].join(" "),
    input: [
      {
        role: "user",
        content:
          body.sourceKind === "text"
            ? [{ type: "input_text", text: source }]
            : [{ type: "input_image", image_url: source, detail: "high" }],
      },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "recipe_draft",
        strict: true,
        schema: recipeDraftSchema,
      },
    },
    reasoning: { effort: "low" },
    tools: [],
    store: false,
    background: false,
    stream: false,
    max_output_tokens: maxOutputTokens,
  };
}

function parseImageDataUrl(value) {
  const prefix = "data:";
  const separator = ";base64,";
  if (!value.startsWith(prefix)) return null;
  const separatorIndex = value.indexOf(separator, prefix.length);
  if (separatorIndex === -1) return null;
  return {
    mimeType: value.slice(prefix.length, separatorIndex),
    payload: value.slice(separatorIndex + separator.length),
  };
}

function extractOutputText(providerBody) {
  if (
    providerBody === null ||
    typeof providerBody !== "object" ||
    providerBody.status !== "completed" ||
    !Array.isArray(providerBody.output)
  ) {
    return null;
  }
  const messages = providerBody.output.filter(
    (item) =>
      item !== null &&
      typeof item === "object" &&
      item.type === "message" &&
      item.role === "assistant" &&
      item.status === "completed"
  );
  if (messages.length !== 1 || !Array.isArray(messages[0].content)) {
    return null;
  }
  const content = messages[0].content;
  if (
    content.length !== 1 ||
    content[0] === null ||
    typeof content[0] !== "object" ||
    content[0].type !== "output_text" ||
    typeof content[0].text !== "string"
  ) {
    return null;
  }
  return content[0].text;
}

function parseRequestBody(value) {
  if (value !== null && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Array.isArray(value) ? null : value;
  }
  if (typeof value !== "string" && !Buffer.isBuffer(value)) return null;
  try {
    const parsed = JSON.parse(String(value));
    return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function isJsonContentType(value) {
  return typeof value === "string" && /^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(value);
}

function readHeader(headers, name) {
  if (headers === null || typeof headers !== "object") return undefined;
  const value = headers[name] ?? headers[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

function isCanonicalBase64(value) {
  if (typeof value !== "string" || value.length === 0 || value.length % 4 !== 0) {
    return false;
  }
  const firstPadding = value.indexOf("=");
  const contentLength = firstPadding === -1 ? value.length : firstPadding;
  const paddingLength = value.length - contentLength;
  if (paddingLength > 2) return false;
  for (let index = 0; index < contentLength; index += 1) {
    const code = value.charCodeAt(index);
    const isBase64Character =
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code === 43 ||
      code === 47;
    if (!isBase64Character) return false;
  }
  for (let index = contentLength; index < value.length; index += 1) {
    if (value[index] !== "=") return false;
  }
  return (
    (paddingLength === 0 && contentLength % 4 === 0) ||
    (paddingLength === 1 && contentLength % 4 === 3) ||
    (paddingLength === 2 && contentLength % 4 === 2)
  );
}

function isNonBlankString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function hasExactKeys(value, expectedKeys) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const keys = Object.keys(value);
  return keys.length === expectedKeys.length && keys.every((key) => expectedKeys.includes(key));
}
