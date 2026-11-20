import type { ClaudeClient, ClaudeMessage, CreateParams } from "../src/claude";
import type { Env } from "../src/env";
import { route } from "../src/router";
import type { Fetcher } from "../src/speak";

export const SECRET = "test-secret-123";

export const env: Env = {
  ANTHROPIC_API_KEY: "sk-test",
  APP_SHARED_SECRET: SECRET,
  CLAUDE_MODEL: "claude-opus-5-5",
  CHAT_EFFORT: "medium",
  DIAGNOSE_EFFORT: "high",
  NUDGE_EFFORT: "low",
};

type Block = Record<string, unknown>;

export function message(content: Block[], stop_reason: string = "end_turn", model = "claude-opus-5-5"): ClaudeMessage {
  return {
    id: `msg_${Math.random().toString(36).slice(2)}`,
    type: "message",
    role: "assistant",
    model,
    content,
    stop_reason,
    stop_sequence: null,
    usage: { input_tokens: 100, output_tokens: 50, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
  } as unknown as ClaudeMessage;
}

export class FakeClaude implements ClaudeClient {
  readonly calls: CreateParams[] = [];
  constructor(private readonly replies: Array<ClaudeMessage | Error>) {}
  async createMessage(params: CreateParams): Promise<ClaudeMessage> {
    // Snapshot the params; the handler mutates its messages array between rounds.
    this.calls.push(structuredClone(params));
    const next = this.replies.shift();
    if (!next) throw new Error("FakeClaude: no more scripted replies");
    if (next instanceof Error) throw next;
    return next;
  }
}

export const garden = {
  schemaVersion: 1,
  today: "2026-07-14",
  timeZone: "America/Chicago",
  gardener: { name: "Sam" },
  inventory: [{ name: "Fish emulsion", category: "fertilizer", quantity: "half a quart", notes: "" }],
  beds: [{ id: "b1", name: "Raised bed 1", kind: "raised", soilType: "loam" }],
  plants: [{ id: "p1", name: "Sungold tomato", crop: "cherry_tomato", bedName: "Raised bed 1", stage: "fruiting" }],
};

export function post(path: string, body: unknown, token = SECRET): Request {
  return new Request(`https://worker.test${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

export function get(path: string, token = SECRET): Request {
  return new Request(`https://worker.test${path}`, { headers: { authorization: `Bearer ${token}` } });
}

export async function call(
  request: Request,
  claude: ClaudeClient,
  options: { env?: Env; fetcher?: Fetcher } = {},
): Promise<Response> {
  return route(request, options.env ?? env, {
    claude: () => claude,
    fetcher: options.fetcher ?? (async () => new Response("unexpected fetch", { status: 500 })),
  });
}
