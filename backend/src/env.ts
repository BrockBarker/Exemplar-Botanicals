export interface Env {
  /** Claude API key (secret). */
  ANTHROPIC_API_KEY?: string;
  /** Shared secret the app sends as a Bearer token (secret). */
  APP_SHARED_SECRET?: string;
  /** ElevenLabs API key (secret, optional). Voice playback is off without it. */
  ELEVENLABS_API_KEY?: string;
  /** ElevenLabs voice ID of David's cloned voice (optional). */
  ELEVENLABS_VOICE_ID?: string;
  ELEVENLABS_MODEL_ID?: string;
  CLAUDE_MODEL?: string;
  CHAT_EFFORT?: string;
  DIAGNOSE_EFFORT?: string;
  NUDGE_EFFORT?: string;
}

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

const EFFORTS: readonly Effort[] = ["low", "medium", "high", "xhigh", "max"];

export const DEFAULT_MODEL = "claude-opus-5-5";

export function modelFor(env: Env): string {
  const m = env.CLAUDE_MODEL?.trim();
  return m ? m : DEFAULT_MODEL;
}

export function effortFrom(value: string | undefined, fallback: Effort): Effort {
  const v = value?.trim().toLowerCase();
  return (EFFORTS as readonly string[]).includes(v ?? "") ? (v as Effort) : fallback;
}

export function voiceConfigured(env: Env): boolean {
  return Boolean(env.ELEVENLABS_API_KEY?.trim() && env.ELEVENLABS_VOICE_ID?.trim());
}
