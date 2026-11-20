import type { Env } from "./env";

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export function errorResponse(err: HttpError): Response {
  return json({ error: { code: err.code, message: err.message } }, err.status);
}

/** Constant-time string comparison so the shared secret can't be guessed by timing. */
export function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ab.length ^ bb.length;
  const len = Math.max(ab.length, bb.length);
  for (let i = 0; i < len; i++) {
    diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  }
  return diff === 0;
}

export function requireAuth(request: Request, env: Env): void {
  const secret = env.APP_SHARED_SECRET?.trim();
  if (!secret) {
    throw new HttpError(500, "not_configured", "APP_SHARED_SECRET is not set on the server.");
  }
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
  if (!token || !safeEqual(token, secret)) {
    throw new HttpError(401, "unauthorized", "Missing or wrong app secret.");
  }
}

/** Reads a JSON body, refusing anything larger than maxBytes. */
export async function readJson(request: Request, maxBytes: number): Promise<unknown> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBytes) {
    throw new HttpError(413, "too_large", `Request body is larger than ${maxBytes} bytes.`);
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).length > maxBytes) {
    throw new HttpError(413, "too_large", `Request body is larger than ${maxBytes} bytes.`);
  }
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new HttpError(400, "bad_json", "Request body is not valid JSON.");
  }
}

export function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function str(v: unknown, max = 2000): string {
  if (typeof v !== "string") return "";
  const t = v.trim();
  return t.length > max ? t.slice(0, max) : t;
}

export function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

export function oneOf<T extends string>(v: unknown, allowed: readonly T[]): T | null {
  return typeof v === "string" && (allowed as readonly string[]).includes(v) ? (v as T) : null;
}
