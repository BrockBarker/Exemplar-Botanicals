import type Anthropic from "@anthropic-ai/sdk";
import { baseParams, type ClaudeClient, logUsage, mapClaudeError, parseJsonOutput } from "./claude";
import { effortFrom, type Env } from "./env";
import { readGarden } from "./garden";
import { HttpError, isRecord, oneOf, str } from "./http";
import { diagnoseSystem } from "./prompts";
import { CONFIDENCE, DIAGNOSIS_OVERALL, FINDING_CATEGORIES, LIKELIHOOD, TIERS, type Tier } from "./vocab";

type ImageMediaType = "image/jpeg" | "image/png" | "image/gif" | "image/webp";
const IMAGE_TYPES: readonly ImageMediaType[] = ["image/jpeg", "image/png", "image/gif", "image/webp"];

/** Base64 of a ~5 MB image. The app sends a ~1568 px JPEG, usually well under 1 MB. */
const MAX_IMAGE_BASE64 = 7_000_000;

export interface Finding {
  issue: string;
  category: (typeof FINDING_CATEGORIES)[number];
  nutrient: string;
  likelihood: (typeof LIKELIHOOD)[number];
  evidence: string;
}

export interface Fix {
  tier: Tier;
  title: string;
  how: string;
  product: string;
  price: string;
  pros: string;
  cons: string;
  usesInventoryItem: string;
}

export interface Diagnosis {
  summary: string;
  overall: (typeof DIAGNOSIS_OVERALL)[number];
  confidence: (typeof CONFIDENCE)[number];
  findings: Finding[];
  fixes: Fix[];
  soilTestSuggested: boolean;
  soilTestReason: string;
  followUp: string;
  journalNote: string;
  photoQualityNote: string;
}

const s = { type: "string" } as const;

/** JSON schema for structured output. Every object closes its properties, as the API requires. */
export const DIAGNOSIS_SCHEMA = {
  type: "object",
  properties: {
    summary: { type: "string", description: "2 to 4 sentences in David's voice: what's going on and the first thing to do." },
    overall: { type: "string", enum: [...DIAGNOSIS_OVERALL] },
    confidence: { type: "string", enum: [...CONFIDENCE] },
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          issue: { type: "string", description: "e.g. 'Nitrogen deficiency' or 'Underwatering in heat'" },
          category: { type: "string", enum: [...FINDING_CATEGORIES] },
          nutrient: { type: "string", description: "Nutrient involved, or empty string" },
          likelihood: { type: "string", enum: [...LIKELIHOOD] },
          evidence: { type: "string", description: "What in the photo or garden data points to this" },
        },
        required: ["issue", "category", "nutrient", "likelihood", "evidence"],
        additionalProperties: false,
      },
    },
    fixes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          tier: { type: "string", enum: [...TIERS] },
          title: s,
          how: { type: "string", description: "Exact steps: amount, dilution, where, when, how often" },
          product: { type: "string", description: "Brand or product name for branded fixes, else empty string" },
          price: { type: "string", description: "Typical US price range for branded or low-cost fixes, else empty string" },
          pros: s,
          cons: s,
          uses_inventory_item: { type: "string", description: "Exact inventory item name for owned fixes, else empty string" },
        },
        required: ["tier", "title", "how", "product", "price", "pros", "cons", "uses_inventory_item"],
        additionalProperties: false,
      },
    },
    soil_test_suggested: { type: "boolean" },
    soil_test_reason: s,
    follow_up: { type: "string", description: "What to watch for and when to check again" },
    journal_note: s,
    photo_quality_note: { type: "string", description: "Empty string if the photo is fine" },
  },
  required: [
    "summary",
    "overall",
    "confidence",
    "findings",
    "fixes",
    "soil_test_suggested",
    "soil_test_reason",
    "follow_up",
    "journal_note",
    "photo_quality_note",
  ],
  additionalProperties: false,
} as const;

function tierRank(t: Tier): number {
  return TIERS.indexOf(t);
}

/** Validates the model's JSON and puts fixes in use-what-you-have order. */
export function normalizeDiagnosis(raw: unknown): Diagnosis {
  if (!isRecord(raw)) throw new HttpError(502, "bad_diagnosis", "The diagnosis came back in an unexpected shape.");
  const findings: Finding[] = (Array.isArray(raw.findings) ? raw.findings : []).filter(isRecord).map((f) => ({
    issue: str(f.issue, 200),
    category: oneOf(f.category, FINDING_CATEGORIES) ?? "other",
    nutrient: str(f.nutrient, 60),
    likelihood: oneOf(f.likelihood, LIKELIHOOD) ?? "possible",
    evidence: str(f.evidence, 600),
  }));
  const fixes: Fix[] = (Array.isArray(raw.fixes) ? raw.fixes : [])
    .filter(isRecord)
    .map((f) => ({
      tier: oneOf(f.tier, TIERS) ?? "branded",
      title: str(f.title, 160),
      how: str(f.how, 1_200),
      product: str(f.product, 160),
      price: str(f.price, 80),
      pros: str(f.pros, 400),
      cons: str(f.cons, 400),
      usesInventoryItem: str(f.uses_inventory_item, 120),
    }))
    .filter((f) => f.title || f.how)
    .map((f, i) => ({ f, i }))
    .sort((a, b) => tierRank(a.f.tier) - tierRank(b.f.tier) || a.i - b.i)
    .map(({ f }) => f);
  return {
    summary: str(raw.summary, 1_500),
    overall: oneOf(raw.overall, DIAGNOSIS_OVERALL) ?? "unclear",
    confidence: oneOf(raw.confidence, CONFIDENCE) ?? "low",
    findings: findings.filter((f) => f.issue),
    fixes,
    soilTestSuggested: raw.soil_test_suggested === true,
    soilTestReason: str(raw.soil_test_reason, 500),
    followUp: str(raw.follow_up, 800),
    journalNote: str(raw.journal_note, 300),
    photoQualityNote: str(raw.photo_quality_note, 500),
  };
}

export async function handleDiagnose(body: unknown, env: Env, claude: ClaudeClient): Promise<{ diagnosis: Diagnosis; model: string }> {
  if (!isRecord(body)) throw new HttpError(400, "bad_body", "Expected a JSON object.");
  const image = body.image;
  if (!isRecord(image)) throw new HttpError(400, "bad_image", "`image` with `mediaType` and `data` is required.");
  const mediaType = oneOf(image.mediaType, IMAGE_TYPES);
  const data = typeof image.data === "string" ? image.data.replace(/\s/g, "") : "";
  if (!mediaType) throw new HttpError(400, "bad_image", "Image must be JPEG, PNG, GIF or WebP.");
  if (!data || !/^[A-Za-z0-9+/]+=*$/.test(data)) throw new HttpError(400, "bad_image", "Image data must be base64.");
  if (data.length > MAX_IMAGE_BASE64) throw new HttpError(413, "image_too_large", "The photo is too large.");

  const garden = readGarden(body.garden);
  const plantName = str(body.plantName, 80);
  const note = str(body.note, 1_000);
  const ask =
    `Diagnose this photo${plantName ? ` of ${plantName}` : ""}.` +
    (note ? ` The gardener says: "${note}"` : " The gardener didn't add a note.");

  const content: Anthropic.Beta.Messages.BetaContentBlockParam[] = [
    { type: "image", source: { type: "base64", media_type: mediaType, data } },
    { type: "text", text: ask },
  ];

  const base = baseParams(env, effortFrom(env.DIAGNOSE_EFFORT, "high"));
  try {
    const response = await claude.createMessage({
      ...base,
      output_config: { ...base.output_config, format: { type: "json_schema", schema: DIAGNOSIS_SCHEMA } },
      max_tokens: 16_000,
      system: diagnoseSystem(garden),
      messages: [{ role: "user", content }],
    });
    logUsage("diagnose", response);
    if (response.stop_reason === "refusal") {
      throw new HttpError(422, "declined", "The coach couldn't look at this photo. Try a different photo of the plant.");
    }
    if (response.stop_reason === "max_tokens") {
      throw new HttpError(502, "truncated", "The diagnosis was cut off. Try again.");
    }
    return { diagnosis: normalizeDiagnosis(parseJsonOutput(response)), model: response.model };
  } catch (err) {
    throw mapClaudeError(err);
  }
}
