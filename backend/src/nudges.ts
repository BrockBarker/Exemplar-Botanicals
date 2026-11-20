import { baseParams, type ClaudeClient, logUsage, mapClaudeError, parseJsonOutput } from "./claude";
import { effortFrom, type Env } from "./env";
import { HttpError, isRecord, str } from "./http";
import { nudgeSystem } from "./prompts";

export interface NudgeDraft {
  id: string;
  kind: string;
  title: string;
  body: string;
}

export interface NudgePhrasing {
  id: string;
  title: string;
  body: string;
}

const MAX_NUDGES = 12;
const TITLE_MAX = 60;
const BODY_MAX = 200;

export const PHRASING_SCHEMA = {
  type: "object",
  properties: {
    phrasings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          body: { type: "string" },
        },
        required: ["id", "title", "body"],
        additionalProperties: false,
      },
    },
  },
  required: ["phrasings"],
  additionalProperties: false,
} as const;

function readDrafts(value: unknown): NudgeDraft[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpError(400, "bad_nudges", "`nudges` must be a non-empty array.");
  }
  const drafts = value
    .filter(isRecord)
    .map((n) => ({ id: str(n.id, 120), kind: str(n.kind, 40), title: str(n.title, 120), body: str(n.body, 400) }))
    .filter((n) => n.id && n.title && n.body);
  if (drafts.length === 0) throw new HttpError(400, "bad_nudges", "Each nudge needs an id, title and body.");
  return drafts.slice(0, MAX_NUDGES);
}

function clipTo(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;
}

/** Rewords app-generated nudges in David's voice. Any nudge the model skips keeps its draft wording. */
export async function handlePhraseNudges(body: unknown, env: Env, claude: ClaudeClient): Promise<{ phrasings: NudgePhrasing[] }> {
  if (!isRecord(body)) throw new HttpError(400, "bad_body", "Expected a JSON object.");
  const drafts = readDrafts(body.nudges);
  const list = drafts.map((d) => ({ id: d.id, kind: d.kind, title: d.title, body: d.body }));

  const base = baseParams(env, effortFrom(env.NUDGE_EFFORT, "low"));
  let rewritten = new Map<string, NudgePhrasing>();
  try {
    const response = await claude.createMessage({
      ...base,
      output_config: { ...base.output_config, format: { type: "json_schema", schema: PHRASING_SCHEMA } },
      max_tokens: 4_000,
      system: nudgeSystem(),
      messages: [{ role: "user", content: `Nudges to rewrite:\n${JSON.stringify(list)}` }],
    });
    logUsage("nudges", response);
    if (response.stop_reason !== "refusal" && response.stop_reason !== "max_tokens") {
      const parsed = parseJsonOutput(response);
      const items = isRecord(parsed) && Array.isArray(parsed.phrasings) ? parsed.phrasings : [];
      rewritten = new Map(
        items
          .filter(isRecord)
          .map((p) => ({ id: str(p.id, 120), title: str(p.title, 200), body: str(p.body, 600) }))
          .filter((p) => p.id && p.title && p.body)
          .map((p) => [p.id, p] as const),
      );
    }
  } catch (err) {
    throw mapClaudeError(err);
  }

  return {
    phrasings: drafts.map((d) => {
      const r = rewritten.get(d.id);
      return {
        id: d.id,
        title: clipTo(r?.title ?? d.title, TITLE_MAX),
        body: clipTo(r?.body ?? d.body, BODY_MAX),
      };
    }),
  };
}
