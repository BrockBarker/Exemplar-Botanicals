import { anthropicClient, type ClaudeClient } from "./claude";
import { handleCoach } from "./coach";
import { handleDiagnose } from "./diagnose";
import { type Env, modelFor, voiceConfigured } from "./env";
import { errorResponse, HttpError, json, readJson, requireAuth } from "./http";
import { handlePhraseNudges } from "./nudges";
import { PERSONA_FILES } from "./persona.generated";
import { type Fetcher, handleSpeak } from "./speak";

export const API_VERSION = "1";

export interface Deps {
  claude: (env: Env) => ClaudeClient;
  fetcher: Fetcher;
}

const defaultDeps: Deps = {
  claude: anthropicClient,
  fetcher: (input, init) => fetch(input, init),
};

const KB = 1024;

export async function route(request: Request, env: Env, deps: Deps = defaultDeps): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";

  try {
    if (path === "/" && request.method === "GET") {
      return json({ name: "exemplar-botanicals", ok: true });
    }
    if (!path.startsWith("/v1/")) throw new HttpError(404, "not_found", "No such endpoint.");

    requireAuth(request, env);

    if (path === "/v1/health" && request.method === "GET") {
      return json({
        ok: true,
        apiVersion: API_VERSION,
        model: modelFor(env),
        claudeConfigured: Boolean(env.ANTHROPIC_API_KEY?.trim()),
        voiceAvailable: voiceConfigured(env),
        persona: PERSONA_FILES.map((f) => ({ name: f.name, status: f.status })),
      });
    }

    if (request.method !== "POST") throw new HttpError(405, "method_not_allowed", "Use POST.");

    switch (path) {
      case "/v1/coach":
        return json(await handleCoach(await readJson(request, 512 * KB), env, deps.claude(env)));
      case "/v1/diagnose":
        return json(await handleDiagnose(await readJson(request, 8 * KB * KB), env, deps.claude(env)));
      case "/v1/nudges/phrase":
        return json(await handlePhraseNudges(await readJson(request, 64 * KB), env, deps.claude(env)));
      case "/v1/speak":
        return await handleSpeak(await readJson(request, 64 * KB), env, deps.fetcher);
      default:
        throw new HttpError(404, "not_found", "No such endpoint.");
    }
  } catch (err) {
    if (err instanceof HttpError) return errorResponse(err);
    console.error("unhandled", err);
    return errorResponse(new HttpError(500, "internal", "Something went wrong on the server."));
  }
}
