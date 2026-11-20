import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { call, FakeClaude, garden, get, message, post } from "./helpers";

describe("auth and health", () => {
  it("rejects requests without the app secret", async () => {
    const res = await call(get("/v1/health", ""), new FakeClaude([]));
    expect(res.status).toBe(401);
  });

  it("rejects a wrong app secret", async () => {
    const res = await call(get("/v1/health", "nope"), new FakeClaude([]));
    expect(res.status).toBe(401);
  });

  it("reports configuration and persona status", async () => {
    const res = await call(get("/v1/health"), new FakeClaude([]));
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.model).toBe("claude-opus-5-5");
    expect(body.voiceAvailable).toBe(false);
    const persona = body.persona as Array<{ name: string; status: string }>;
    expect(persona.map((p) => p.name)).toEqual(["about", "voice", "opinions", "products", "sample-answers"]);
  });

  it("returns 404 for unknown paths", async () => {
    const res = await call(post("/v1/nope", {}), new FakeClaude([]));
    expect(res.status).toBe(404);
  });
});

describe("/v1/coach", () => {
  it("sends the persona (cached), the garden, and the conversation", async () => {
    const claude = new FakeClaude([message([{ type: "text", text: "Water deeply tonight." }])]);
    const res = await call(
      post("/v1/coach", {
        messages: [
          { role: "assistant", text: "Hi, I'm David. What's growing?" },
          { role: "user", text: "It's going to be 98 tomorrow. What should I do?" },
        ],
        garden,
        context: { kind: "nudge", text: "Heat wave Thursday" },
      }),
      claude,
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { reply: string; actions: unknown[] };
    expect(body.reply).toBe("Water deeply tonight.");
    expect(body.actions).toEqual([]);

    const params = claude.calls[0]!;
    expect(params.model).toBe("claude-opus-5-5");
    expect(params.output_config?.effort).toBe("medium");
    expect(params.fallbacks).toBe("default");
    expect(params.betas).toContain("server-side-fallback-2026-07-01");
    expect(params.tool_choice).toBeUndefined();

    const system = params.system as Array<{ text: string; cache_control?: unknown }>;
    expect(system[0]!.cache_control).toEqual({ type: "ephemeral" });
    expect(system[0]!.text).toContain("Strictly organic");
    expect(system[0]!.text).toContain("How David talks");
    expect(system[0]!.text).not.toContain("<!--");
    expect(system[1]!.cache_control).toBeUndefined();
    expect(system[1]!.text).toContain("Today is 2026-07-14");
    expect(system[1]!.text).toContain("Sungold tomato");

    // Leading assistant greeting is dropped; the nudge context rides along with the question.
    expect(params.messages).toHaveLength(1);
    const first = params.messages[0]!;
    expect(first.role).toBe("user");
    expect(JSON.stringify(first.content)).toContain("Heat wave Thursday");
    expect(JSON.stringify(first.content)).toContain("98 tomorrow");
  });

  it("runs record-keeping tools and returns the actions for the app", async () => {
    const claude = new FakeClaude([
      message(
        [
          { type: "thinking", thinking: "", signature: "sig" },
          { type: "text", text: "Nice work." },
          {
            type: "tool_use",
            id: "toolu_1",
            name: "log_journal_entry",
            input: { date: "yesterday", kind: "feeding", what: "fish emulsion", plant_name: "Sungold tomato", amount: "1 tbsp/gal" },
          },
          { type: "tool_use", id: "toolu_2", name: "update_inventory", input: { action: "add" } },
        ],
        "tool_use",
      ),
      message([{ type: "text", text: "I logged that. Next feed in about three weeks." }]),
    ]);
    const res = await call(
      post("/v1/coach", { messages: [{ role: "user", text: "Fed the Sungold fish emulsion yesterday" }], garden }),
      claude,
    );
    const body = (await res.json()) as { reply: string; actions: Array<Record<string, unknown>> };
    expect(body.reply).toBe("Nice work.\n\nI logged that. Next feed in about three weeks.");
    expect(body.actions).toHaveLength(1);
    expect(body.actions[0]).toMatchObject({
      type: "journal",
      kind: "feeding",
      what: "fish emulsion",
      plantName: "Sungold tomato",
      // An unparseable date falls back to the gardener's "today".
      date: "2026-07-14",
    });

    const second = claude.calls[1]!;
    const assistantTurn = second.messages[1]!;
    expect(assistantTurn.role).toBe("assistant");
    // The assistant turn goes back unchanged, thinking block included.
    expect(JSON.stringify(assistantTurn.content)).toContain('"type":"thinking"');
    const results = second.messages[2]!.content as unknown as Array<Record<string, unknown>>;
    expect(results).toEqual([
      { type: "tool_result", tool_use_id: "toolu_1", content: "Saved." },
      {
        type: "tool_result",
        tool_use_id: "toolu_2",
        is_error: true,
        content: "Not saved: a required field was missing or invalid.",
      },
    ]);
  });

  it("answers kindly when the model declines", async () => {
    const claude = new FakeClaude([message([], "refusal")]);
    const res = await call(post("/v1/coach", { messages: [{ role: "user", text: "hi" }], garden }), claude);
    const body = (await res.json()) as { reply: string };
    expect(res.status).toBe(200);
    expect(body.reply).toContain("Ask me anything about your garden");
  });

  it("requires the last message to be from the gardener", async () => {
    const res = await call(
      post("/v1/coach", { messages: [{ role: "user", text: "hi" }, { role: "assistant", text: "hello" }] }),
      new FakeClaude([]),
    );
    expect(res.status).toBe(400);
  });

  it("maps a rate limit to 429", async () => {
    const err = new Anthropic.RateLimitError(429, { type: "error" }, "rate limited", new Headers());
    const res = await call(post("/v1/coach", { messages: [{ role: "user", text: "hi" }] }), new FakeClaude([err]));
    expect(res.status).toBe(429);
    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("busy");
  });

  it("skips refusal fallbacks for models that don't support them", async () => {
    const claude = new FakeClaude([message([{ type: "text", text: "ok" }], "end_turn", "claude-haiku-5-5")]);
    await call(post("/v1/coach", { messages: [{ role: "user", text: "hi" }] }), claude, {
      env: { ANTHROPIC_API_KEY: "k", APP_SHARED_SECRET: "test-secret-123", CLAUDE_MODEL: "claude-haiku-5-5" },
    });
    expect(claude.calls[0]!.fallbacks).toBeUndefined();
    expect(claude.calls[0]!.betas).toBeUndefined();
  });
});
