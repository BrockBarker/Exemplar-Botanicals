import { describe, expect, it } from "vitest";
import { DIAGNOSIS_SCHEMA } from "../src/diagnose";
import { PHRASING_SCHEMA } from "../src/nudges";
import { speechText } from "../src/text";
import { normalizeAction } from "../src/tools";
import { call, env, FakeClaude, garden, message, post } from "./helpers";

const IMAGE = { mediaType: "image/jpeg", data: "/9j/4AAQSkZJRgABAQAAAQABAAD" };

const diagnosisJson = {
  summary: "Lower leaves are yellowing evenly. That's hungry, not thirsty.",
  overall: "nutrient_deficiency",
  confidence: "medium",
  findings: [
    { issue: "Nitrogen deficiency", category: "deficiency", nutrient: "nitrogen", likelihood: "likely", evidence: "Uniform yellowing on older leaves" },
  ],
  fixes: [
    { tier: "branded", title: "Blood meal", how: "1 tbsp around the plant", product: "Down to Earth Blood Meal", price: "$12 to $20", pros: "fast", cons: "can burn", uses_inventory_item: "" },
    { tier: "free", title: "Diluted urine", how: "1:10 on the soil", product: "", price: "", pros: "free", cons: "", uses_inventory_item: "" },
    { tier: "owned", title: "Fish emulsion", how: "1 tbsp per gallon", product: "", price: "", pros: "", cons: "smells", uses_inventory_item: "Fish emulsion" },
  ],
  soil_test_suggested: false,
  soil_test_reason: "",
  follow_up: "New growth should green up in a week.",
  journal_note: "Photo check: nitrogen deficiency on Sungold.",
  photo_quality_note: "",
};

describe("/v1/diagnose", () => {
  it("returns a diagnosis with fixes in use-what-you-have order", async () => {
    const claude = new FakeClaude([message([{ type: "text", text: JSON.stringify(diagnosisJson) }])]);
    const res = await call(post("/v1/diagnose", { image: IMAGE, plantName: "Sungold tomato", note: "yellow leaves", garden }), claude);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { diagnosis: { fixes: Array<{ tier: string; usesInventoryItem: string }>; overall: string } };
    expect(body.diagnosis.overall).toBe("nutrient_deficiency");
    expect(body.diagnosis.fixes.map((f) => f.tier)).toEqual(["owned", "free", "branded"]);
    expect(body.diagnosis.fixes[0]!.usesInventoryItem).toBe("Fish emulsion");

    const params = claude.calls[0]!;
    expect(params.output_config?.effort).toBe("high");
    expect(params.output_config?.format?.type).toBe("json_schema");
    const content = params.messages[0]!.content as unknown as Array<Record<string, unknown>>;
    expect(content[0]!.type).toBe("image");
    expect(JSON.stringify(content[1])).toContain("Sungold tomato");
  });

  it("recovers the JSON when a refusal fallback switched models mid-reply", async () => {
    const claude = new FakeClaude([
      message([
        { type: "text", text: '{"summary": "Lower lea' },
        { type: "fallback", from: { model: "claude-opus-5-5" }, to: { model: "claude-opus-5" }, trigger: { type: "refusal" } },
        { type: "text", text: JSON.stringify(diagnosisJson) },
      ]),
    ]);
    const res = await call(post("/v1/diagnose", { image: IMAGE, garden }), claude);
    expect(res.status).toBe(200);
  });

  it("rejects a missing or non-base64 image", async () => {
    const claude = new FakeClaude([]);
    expect((await call(post("/v1/diagnose", { garden }), claude)).status).toBe(400);
    expect((await call(post("/v1/diagnose", { image: { mediaType: "image/jpeg", data: "not base64!" } }), claude)).status).toBe(400);
    expect((await call(post("/v1/diagnose", { image: { mediaType: "image/tiff", data: "AAAA" } }), claude)).status).toBe(400);
    expect(claude.calls).toHaveLength(0);
  });

  it("explains a declined photo", async () => {
    const res = await call(post("/v1/diagnose", { image: IMAGE }), new FakeClaude([message([], "refusal")]));
    expect(res.status).toBe(422);
  });
});

describe("/v1/nudges/phrase", () => {
  it("rewords nudges and keeps the draft for any the model skipped", async () => {
    const claude = new FakeClaude([
      message([
        {
          type: "text",
          text: JSON.stringify({ phrasings: [{ id: "n1", title: "Heat's coming", body: "x".repeat(400) }] }),
        },
      ]),
    ]);
    const res = await call(
      post("/v1/nudges/phrase", {
        nudges: [
          { id: "n1", kind: "heat_stress", title: "Heat wave Thursday", body: "Water deeply Wednesday evening." },
          { id: "n2", kind: "staking", title: "Stake the Sungold", body: "It's 3 weeks in and not staked yet." },
        ],
      }),
      claude,
    );
    const body = (await res.json()) as { phrasings: Array<{ id: string; title: string; body: string }> };
    expect(body.phrasings).toHaveLength(2);
    expect(body.phrasings[0]!.title).toBe("Heat's coming");
    expect(body.phrasings[0]!.body.length).toBeLessThanOrEqual(200);
    expect(body.phrasings[1]).toEqual({ id: "n2", title: "Stake the Sungold", body: "It's 3 weeks in and not staked yet." });
    expect(claude.calls[0]!.output_config?.effort).toBe("low");
  });
});

describe("/v1/speak", () => {
  const voiceEnv = { ...env, ELEVENLABS_API_KEY: "el-key", ELEVENLABS_VOICE_ID: "voice123" };

  it("is off until ElevenLabs is configured", async () => {
    const res = await call(post("/v1/speak", { text: "hello" }), new FakeClaude([]));
    expect(res.status).toBe(404);
  });

  it("sends plain text to ElevenLabs and streams back MP3 audio", async () => {
    let seenUrl = "";
    let seenInit: RequestInit | undefined;
    const res = await call(post("/v1/speak", { text: "**Water** deeply at 85°F.\n- then mulch" }), new FakeClaude([]), {
      env: voiceEnv,
      fetcher: async (url, init) => {
        seenUrl = url;
        seenInit = init;
        return new Response(new Uint8Array([1, 2, 3]), { status: 200, headers: { "content-type": "audio/mpeg" } });
      },
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/mpeg");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(new Uint8Array([1, 2, 3]));
    expect(seenUrl).toBe("https://api.elevenlabs.io/v1/text-to-speech/voice123?output_format=mp3_44100_128");
    const headers = seenInit!.headers as Record<string, string>;
    expect(headers["xi-api-key"]).toBe("el-key");
    const sent = JSON.parse(seenInit!.body as string) as { text: string; model_id: string };
    expect(sent.text).toBe("Water deeply at 85 degrees.\nthen mulch");
    expect(sent.model_id).toBe("eleven_multilingual_v2");
  });

  it("reports a rejected ElevenLabs key", async () => {
    const res = await call(post("/v1/speak", { text: "hi" }), new FakeClaude([]), {
      env: voiceEnv,
      fetcher: async () => new Response("bad key", { status: 401 }),
    });
    expect(res.status).toBe(500);
    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("voice_key");
  });
});

describe("normalizeAction", () => {
  it("validates and normalizes each tool", () => {
    expect(normalizeAction("update_plant", { plant_name: "Basil", stage: "flowering", staked: false, count: 2.4 }, "2026-07-14")).toMatchObject({
      type: "plant",
      plantName: "Basil",
      stage: "flowering",
      staked: false,
      count: 2,
      removed: false,
    });
    expect(normalizeAction("update_bed", { bed_name: "Back bed", soil_ph: 14, soil_type: "clay" }, "2026-07-14")).toMatchObject({
      type: "bed",
      soilType: "clay",
      soilPH: null,
    });
    expect(normalizeAction("update_budget", { monthly_dollars: 25 }, "2026-07-14")).toMatchObject({ type: "budget", monthlyDollars: 25 });
    expect(normalizeAction("remember_garden_fact", { fact: "Has a 50 gallon rain barrel" }, "2026-07-14")).toMatchObject({
      type: "fact",
      category: "other",
    });
    expect(normalizeAction("update_plant", {}, "2026-07-14")).toBeNull();
    expect(normalizeAction("delete_everything", { x: 1 }, "2026-07-14")).toBeNull();
  });
});

describe("structured output schemas", () => {
  // The API requires every object to list all its properties as required and close extras.
  function checkObjects(schema: unknown, path = "$"): string[] {
    const problems: string[] = [];
    if (typeof schema !== "object" || schema === null) return problems;
    const s = schema as Record<string, unknown>;
    if (s.type === "object") {
      const props = Object.keys((s.properties as Record<string, unknown>) ?? {});
      const required = (s.required as string[]) ?? [];
      if (s.additionalProperties !== false) problems.push(`${path}: additionalProperties must be false`);
      for (const p of props) if (!required.includes(p)) problems.push(`${path}.${p} is not required`);
      for (const [k, v] of Object.entries((s.properties as Record<string, unknown>) ?? {})) problems.push(...checkObjects(v, `${path}.${k}`));
    }
    if (s.type === "array") problems.push(...checkObjects(s.items, `${path}[]`));
    return problems;
  }

  it("diagnosis and phrasing schemas are closed and fully required", () => {
    expect(checkObjects(DIAGNOSIS_SCHEMA)).toEqual([]);
    expect(checkObjects(PHRASING_SCHEMA)).toEqual([]);
  });
});

describe("speechText", () => {
  it("strips Markdown so replies read naturally", () => {
    expect(speechText("## Plan\n1. **Water** _deeply_\n2. See [this](https://x.test)\n`code`")).toBe(
      "Plan\n1. Water deeply\n2. See this\ncode",
    );
  });
});

