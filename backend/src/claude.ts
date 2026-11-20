import Anthropic from "@anthropic-ai/sdk";
import { type Effort, type Env, modelFor } from "./env";
import { HttpError } from "./http";

export type CreateParams = Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;
export type ClaudeMessage = Anthropic.Beta.Messages.BetaMessage;

/** The one call the handlers need. Tests pass a fake; production wraps the Anthropic SDK. */
export interface ClaudeClient {
  createMessage(params: CreateParams): Promise<ClaudeMessage>;
}

export function anthropicClient(env: Env): ClaudeClient {
  const apiKey = env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    throw new HttpError(500, "not_configured", "ANTHROPIC_API_KEY is not set on the server.");
  }
  const client = new Anthropic({ apiKey, maxRetries: 2, timeout: 120_000 });
  return {
    createMessage: (params) => client.beta.messages.create(params),
  };
}

/**
 * Models that accept the server-side refusal fallback. On these we opt in by default so a
 * rare safety-classifier decline on an ordinary garden question is retried on a fallback
 * model inside the same call instead of failing.
 */
function supportsServerFallback(model: string): boolean {
  return /^claude-(opus-5|sonnet-5-5|fable-5)/.test(model);
}

/** Shared request settings: model, effort and (where supported) refusal fallbacks. */
export function baseParams(env: Env, effort: Effort): Pick<CreateParams, "model" | "output_config" | "betas" | "fallbacks"> {
  const model = modelFor(env);
  const params: Pick<CreateParams, "model" | "output_config" | "betas" | "fallbacks"> = {
    model,
    output_config: { effort },
  };
  if (supportsServerFallback(model)) {
    params.betas = ["server-side-fallback-2026-07-01"];
    params.fallbacks = "default";
  }
  return params;
}

export function textOf(message: ClaudeMessage): string {
  return message.content
    .filter((b): b is Anthropic.Beta.Messages.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("\n\n")
    .trim();
}

/**
 * Parses a structured-output reply. If a refusal fallback switched models mid-reply, the
 * content holds a `fallback` block between text blocks; try the whole text first, then only
 * the text the final model wrote.
 */
export function parseJsonOutput(message: ClaudeMessage): unknown {
  const all: string[] = [];
  let afterLastFallback: string[] = [];
  for (const block of message.content) {
    if (block.type === "text") {
      all.push(block.text);
      afterLastFallback.push(block.text);
    } else if (block.type === "fallback") {
      afterLastFallback = [];
    }
  }
  for (const candidate of [all.join(""), afterLastFallback.join("")]) {
    try {
      return JSON.parse(candidate) as unknown;
    } catch {
      // try the next candidate
    }
  }
  throw new HttpError(502, "bad_output", "The coach's answer came back garbled. Try again.");
}

export function logUsage(route: string, message: ClaudeMessage): void {
  const u = message.usage;
  console.log(
    JSON.stringify({
      route,
      model: message.model,
      stop: message.stop_reason,
      input: u.input_tokens,
      output: u.output_tokens,
      cacheRead: u.cache_read_input_tokens ?? 0,
      cacheWrite: u.cache_creation_input_tokens ?? 0,
    }),
  );
}

/** Maps SDK errors to HTTP errors the app understands. */
export function mapClaudeError(err: unknown): HttpError {
  if (err instanceof HttpError) return err;
  if (err instanceof Anthropic.RateLimitError) {
    return new HttpError(429, "busy", "The coach is busy right now. Try again in a minute.");
  }
  if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
    return new HttpError(500, "server_key", "The server's Claude API key was rejected.");
  }
  if (err instanceof Anthropic.BadRequestError) {
    console.error("claude bad request", err.message);
    return new HttpError(502, "claude_bad_request", "The coach couldn't process that request.");
  }
  if (err instanceof Anthropic.APIConnectionError) {
    return new HttpError(502, "claude_unreachable", "Couldn't reach the coach service. Try again.");
  }
  if (err instanceof Anthropic.APIError) {
    console.error("claude api error", err.status, err.message);
    return new HttpError(502, "claude_error", "The coach service had a problem. Try again.");
  }
  console.error("unexpected error", err);
  return new HttpError(500, "internal", "Something went wrong on the server.");
}
