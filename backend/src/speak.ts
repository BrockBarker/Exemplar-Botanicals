import { type Env, voiceConfigured } from "./env";
import { HttpError, isRecord, str } from "./http";
import { clip, speechText } from "./text";

/** ElevenLabs allows longer input, but coach replies are short; this keeps cost predictable. */
const MAX_SPEECH_CHARS = 4_500;

export type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

/**
 * Reads a coach reply aloud in David's cloned voice (ElevenLabs text-to-speech).
 * Only used when the gardener turns the voice option on; the app caches the audio per reply.
 */
export async function handleSpeak(body: unknown, env: Env, fetcher: Fetcher): Promise<Response> {
  if (!voiceConfigured(env)) {
    throw new HttpError(404, "voice_off", "David's voice isn't set up on the server yet.");
  }
  if (!isRecord(body)) throw new HttpError(400, "bad_body", "Expected a JSON object.");
  const text = clip(speechText(str(body.text, 20_000)), MAX_SPEECH_CHARS);
  if (!text) throw new HttpError(400, "bad_text", "`text` is required.");

  const voiceId = encodeURIComponent(env.ELEVENLABS_VOICE_ID!.trim());
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`;
  let upstream: Response;
  try {
    upstream = await fetcher(url, {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY!.trim(),
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: JSON.stringify({
        text,
        model_id: env.ELEVENLABS_MODEL_ID?.trim() || "eleven_multilingual_v2",
        voice_settings: { stability: 0.5, similarity_boost: 0.8 },
      }),
    });
  } catch (err) {
    console.error("elevenlabs unreachable", err);
    throw new HttpError(502, "voice_unreachable", "Couldn't reach the voice service.");
  }
  if (!upstream.ok) {
    const detail = await upstream.text().catch(() => "");
    console.error("elevenlabs error", upstream.status, detail.slice(0, 300));
    if (upstream.status === 401) throw new HttpError(500, "voice_key", "The server's ElevenLabs key was rejected.");
    if (upstream.status === 429) throw new HttpError(429, "busy", "The voice service is busy. Try again in a minute.");
    throw new HttpError(502, "voice_error", "The voice service had a problem.");
  }
  return new Response(upstream.body, {
    status: 200,
    headers: { "content-type": "audio/mpeg", "cache-control": "no-store" },
  });
}
