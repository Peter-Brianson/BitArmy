import { DurableObject } from "cloudflare:workers";

export class SignalRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sessions = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/ws") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];

      server.accept();

      const id = crypto.randomUUID();
      this.sessions.set(id, server);

      server.addEventListener("message", (event) => {
        let data = null;

        try {
          data = JSON.parse(event.data);
        } catch {
          return;
        }

        for (const [otherId, socket] of this.sessions.entries()) {
          if (otherId === id) {
            continue;
          }

          try {
            socket.send(JSON.stringify(data));
          } catch {}
        }
      });

      const cleanup = () => {
        this.sessions.delete(id);
      };

      server.addEventListener("close", cleanup);
      server.addEventListener("error", cleanup);

      return new Response(null, {
        status: 101,
        webSocket: client
      });
    }

    return new Response("BitArmy signaling worker online");
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/room/")) {
      const roomCode = url.pathname.slice("/room/".length) || "default";
      const id = env.SIGNAL_ROOMS.idFromName(roomCode);
      const stub = env.SIGNAL_ROOMS.get(id);
      return stub.fetch(request);
    }

    return new Response("BitArmy signaling root online");
  }
};