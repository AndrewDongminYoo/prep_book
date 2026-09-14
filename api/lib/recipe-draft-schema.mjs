const confidenceValues = ["high", "medium", "low"];
const behaviorValues = ["proportional", "perBatch", "fixedOnce", "manual"];

const nullableString = {
  type: ["string", "null"],
};

const nullableDecimalString = {
  anyOf: [{ type: "string", pattern: "^(?:0|[1-9]\\d*)(?:\\.\\d+)?$" }, { type: "null" }],
};

const stringField = {
  type: "object",
  additionalProperties: false,
  properties: {
    value: nullableString,
    evidence: { type: "string" },
    confidence: { type: "string", enum: confidenceValues },
    issues: { type: "array", items: { type: "string" } },
  },
  required: ["value", "evidence", "confidence", "issues"],
};

const behaviorField = {
  type: "object",
  additionalProperties: false,
  properties: {
    value: {
      anyOf: [{ type: "string", enum: behaviorValues }, { type: "null" }],
    },
    evidence: { type: "string" },
    confidence: { type: "string", enum: confidenceValues },
    issues: { type: "array", items: { type: "string" } },
  },
  required: ["value", "evidence", "confidence", "issues"],
};

const quantityField = {
  type: "object",
  additionalProperties: false,
  properties: {
    value: nullableDecimalString,
    evidence: { type: "string" },
    confidence: { type: "string", enum: confidenceValues },
    issues: { type: "array", items: { type: "string" } },
  },
  required: ["value", "evidence", "confidence", "issues"],
};

const yieldDraft = {
  type: "object",
  additionalProperties: false,
  properties: {
    amount: { $ref: "#/$defs/quantityField" },
    unit: { $ref: "#/$defs/stringField" },
  },
  required: ["amount", "unit"],
};

const recipeDetails = {
  type: "object",
  additionalProperties: false,
  properties: {
    name: { $ref: "#/$defs/stringField" },
    baseYield: { $ref: "#/$defs/yieldDraft" },
    maxBatchYield: {
      anyOf: [{ $ref: "#/$defs/yieldDraft" }, { type: "null" }],
    },
    preparationNotes: {
      type: "array",
      items: { $ref: "#/$defs/stringField" },
    },
  },
  required: ["name", "baseYield", "maxBatchYield", "preparationNotes"],
};

const recipeComponent = {
  type: "object",
  additionalProperties: false,
  properties: {
    name: { $ref: "#/$defs/stringField" },
    amount: { $ref: "#/$defs/quantityField" },
    unit: { $ref: "#/$defs/stringField" },
    behavior: { $ref: "#/$defs/behaviorField" },
    note: {
      anyOf: [{ $ref: "#/$defs/stringField" }, { type: "null" }],
    },
  },
  required: ["name", "amount", "unit", "behavior", "note"],
};

export const recipeDraftSchema = deepFreeze({
  type: "object",
  additionalProperties: false,
  properties: {
    schemaVersion: { type: "integer", const: 1 },
    sourceKind: { type: "string", enum: ["text", "image"] },
    recipe: { $ref: "#/$defs/recipeDetails" },
    components: {
      type: "array",
      items: { $ref: "#/$defs/recipeComponent" },
    },
  },
  required: ["schemaVersion", "sourceKind", "recipe", "components"],
  $defs: {
    stringField,
    behaviorField,
    quantityField,
    yieldDraft,
    recipeDetails,
    recipeComponent,
  },
});

export function validateRecipeDraft(value, { sourceKind } = {}) {
  if (!hasExactKeys(value, ["schemaVersion", "sourceKind", "recipe", "components"])) {
    return false;
  }
  if (
    value.schemaVersion !== 1 ||
    !["text", "image"].includes(value.sourceKind) ||
    (sourceKind !== undefined && value.sourceKind !== sourceKind) ||
    !validateRecipe(value.recipe) ||
    !Array.isArray(value.components) ||
    !value.components.every(validateComponent)
  ) {
    return false;
  }
  return true;
}

function validateRecipe(value) {
  if (!hasExactKeys(value, ["name", "baseYield", "maxBatchYield", "preparationNotes"])) {
    return false;
  }
  return (
    validateStringField(value.name) &&
    validateYield(value.baseYield) &&
    (value.maxBatchYield === null || validateYield(value.maxBatchYield)) &&
    Array.isArray(value.preparationNotes) &&
    value.preparationNotes.every(validateStringField)
  );
}

function validateYield(value) {
  return (
    hasExactKeys(value, ["amount", "unit"]) &&
    validateQuantityField(value.amount) &&
    validateStringField(value.unit)
  );
}

function validateComponent(value) {
  if (!hasExactKeys(value, ["name", "amount", "unit", "behavior", "note"])) {
    return false;
  }
  if (
    !validateStringField(value.name) ||
    !validateQuantityField(value.amount) ||
    !validateStringField(value.unit) ||
    !validateBehaviorField(value.behavior) ||
    !(value.note === null || validateStringField(value.note))
  ) {
    return false;
  }
  return !(
    value.behavior.value === "manual" &&
    (value.amount.value !== null || value.unit.value !== null)
  );
}

function validateStringField(value) {
  return validateField(
    value,
    (fieldValue) =>
      fieldValue === null || (typeof fieldValue === "string" && fieldValue.trim().length > 0)
  );
}

function validateQuantityField(value) {
  return validateField(
    value,
    (fieldValue) =>
      fieldValue === null ||
      (typeof fieldValue === "string" && /^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(fieldValue))
  );
}

function validateBehaviorField(value) {
  return validateField(
    value,
    (fieldValue) => fieldValue === null || behaviorValues.includes(fieldValue)
  );
}

function validateField(value, validateValue) {
  if (
    !hasExactKeys(value, ["value", "evidence", "confidence", "issues"]) ||
    !validateValue(value.value) ||
    typeof value.evidence !== "string" ||
    !confidenceValues.includes(value.confidence) ||
    !Array.isArray(value.issues) ||
    !value.issues.every((issue) => typeof issue === "string")
  ) {
    return false;
  }
  return value.value === null || value.evidence.trim().length > 0;
}

function hasExactKeys(value, expectedKeys) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const keys = Object.keys(value);
  return keys.length === expectedKeys.length && keys.every((key) => expectedKeys.includes(key));
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}
