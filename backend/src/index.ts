import type { Env } from "./env";
import { route } from "./router";

// The Worker entry point. Keep this module's only export the default handler: the Workers
// runtime treats every named export of the main module as an entrypoint.
export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return route(request, env);
  },
} satisfies ExportedHandler<Env>;
