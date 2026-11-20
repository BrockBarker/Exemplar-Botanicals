import type Anthropic from "@anthropic-ai/sdk";
import { baseParams, type ClaudeClient, logUsage, mapClaudeError } from "./claude";
import { effortFrom, type Env } from "./env";
import { readGarden } from "./garden";
import { HttpError, isRecord, str } from "./http";
import { coachSystem } from "./prompts";
import { COACH_TOOLS, type CoachAction, normalizeAction } from "./tools";

type MessageParam = Anthropic.Beta.Messages.BetaMessageParam;
type ToolResult = Anthropic.Beta.Messages.BetaToolResultBlockParam;

export interface CoachReply {
  reply: string;
  actions: CoachAction[];
  model: string;
}

const MAX_TURNS = 40;
const MAX_TURN_CHARS = 8_000;
const MAX_TOOL_ROUNDS = 5;

const REFUSAL_REPLY =
  "I can't help with that one here. Ask me anything about your garden, though: watering, feeding, soil, or what's going on with a plant.";

interface ChatTurn {
  role: "user" | "assistant";
  text: string;
}

function readTurns(value: unknown): ChatTurn[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpError(400, "bad_messages", "`messages` must be a non-empty array.");
  }
  const turns: ChatTurn[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    const role = item.role === "assistant" ? "assistant" : item.role === "user" ? "user" : null;
    const text = str(item.text, MAX_TURN_CHARS);
    if (role && text) turns.push({ role, text });
  }
  // Keep the most recent turns, starting from a user turn (the API requires that).
  let recent = turns.slice(-MAX_TURNS);
  const firstUser = recent.findIndex((t) => t.role === "user");
  recent = firstUser === -1 ? [] : recent.slice(firstUser);
  const last = recent[recent.length - 1];
  if (!last || last.role !== "user") {
    throw new HttpError(400, "bad_messages", "The last message must be from the gardener.");
  }
  return recent;
}

/** Optional note about where the question came from, e.g. a nudge the gardener tapped. */
function readContextNote(value: unknown): string {
  if (!isRecord(value)) return "";
  const kind = str(value.kind, 30);
  const text = str(value.text, 1_000);
  if (!text) return "";
  return kind === "nudge"
    ? `(The gardener opened this chat from a nudge the app sent: "${text}")`
    : `(Context from the app: ${text})`;
}

export async function handleCoach(body: unknown, env: Env, claude: ClaudeClient): Promise<CoachReply> {
  if (!isRecord(body)) throw new HttpError(400, "bad_body", "Expected a JSON object.");
  const turns = readTurns(body.messages);
  const garden = readGarden(body.garden);
  const contextNote = readContextNote(body.context);

  const messages: MessageParam[] = turns.map((t, i) => {
    const isLast = i === turns.length - 1;
    if (isLast && contextNote) {
      return {
        role: "user",
        content: [
          { type: "text", text: contextNote },
          { type: "text", text: t.text },
        ],
      };
    }
    return { role: t.role, content: t.text };
  });

  const system = coachSystem(garden);
  const base = baseParams(env, effortFrom(env.CHAT_EFFORT, "medium"));
  const actions: CoachAction[] = [];
  const replyParts: string[] = [];
  let model = base.model;

  try {
    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const response = await claude.createMessage({
        ...base,
        max_tokens: 8_000,
        system,
        tools: COACH_TOOLS,
        messages,
      });
      logUsage("coach", response);
      model = response.model;

      if (response.stop_reason === "refusal") {
        return { reply: replyParts.length ? replyParts.join("\n\n") : REFUSAL_REPLY, actions, model };
      }

      for (const block of response.content) {
        if (block.type === "text" && block.text.trim()) replyParts.push(block.text.trim());
      }

      const toolUses = response.content.filter(
        (b): b is Anthropic.Beta.Messages.BetaToolUseBlock => b.type === "tool_use",
      );

      if (response.stop_reason === "pause_turn") {
        messages.push({ role: "assistant", content: response.content });
        continue;
      }
      if (response.stop_reason !== "tool_use" || toolUses.length === 0) {
        break;
      }

      // Pass the assistant turn back unchanged (thinking and fallback blocks included).
      messages.push({ role: "assistant", content: response.content });
      const results: ToolResult[] = toolUses.map((use) => {
        const action = normalizeAction(use.name, use.input, garden.today);
        if (action) {
          actions.push(action);
          return { type: "tool_result", tool_use_id: use.id, content: "Saved." };
        }
        return {
          type: "tool_result",
          tool_use_id: use.id,
          is_error: true,
          content: "Not saved: a required field was missing or invalid.",
        };
      });
      messages.push({ role: "user", content: results });
    }
  } catch (err) {
    throw mapClaudeError(err);
  }

  let reply = replyParts.join("\n\n").trim();
  if (!reply) {
    reply = actions.length ? "Got it. I've noted that." : "Sorry, I lost my train of thought. Could you ask that again?";
  }
  return { reply, actions, model };
}
