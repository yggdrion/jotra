// Lobby/signaling server: WebSocket on /ws, health on /healthz, Prometheus metrics on /metrics.
// Environment: PORT (8080), TURN_HOST (empty = no STUN/TURN), TURN_PORT (3478),
// TURN_SECRET (empty = STUN only).

import type { ServerWebSocket } from "bun";
import { Lobby, type Config } from "./rooms";

export const PROTOCOL = 1;

export function startServer(port: number, config: Partial<Config> = {}) {
  const lobby = new Lobby({
    protocol: PROTOCOL,
    turnHost: process.env.TURN_HOST ?? "",
    turnPort: Number(process.env.TURN_PORT ?? 3478),
    turnSecret: process.env.TURN_SECRET ?? "",
    // Rooms live as long as their server, so credentials must outlast a long session.
    turnTtlSeconds: 24 * 3600,
    // The game server pings every 20 s.
    roomTimeoutMs: 60_000,
    guestTimeoutMs: 120_000,
    maxGuests: 10,
    ...config,
  });
  const sweeper = setInterval(() => lobby.sweep(), 10_000);
  let sockets = 0;

  const server = Bun.serve({
    port,
    fetch(req, srv) {
      const path = new URL(req.url).pathname;
      if (path === "/ws") {
        return srv.upgrade(req) ? undefined : new Response("expected websocket", { status: 400 });
      }
      if (path === "/healthz") return new Response("ok");
      if (path === "/metrics") return new Response(metrics(lobby, sockets));
      return new Response("not found", { status: 404 });
    },
    websocket: {
      // Signaling is a few small messages per player.
      maxPayloadLength: 64 * 1024,
      open() {
        sockets++;
      },
      message(ws: ServerWebSocket<unknown>, message) {
        lobby.handle(ws, String(message));
      },
      close(ws: ServerWebSocket<unknown>) {
        sockets--;
        lobby.leave(ws);
      },
    },
  });

  return {
    server,
    lobby,
    stop() {
      clearInterval(sweeper);
      server.stop(true);
    },
  };
}

function metrics(lobby: Lobby, sockets: number): string {
  const lines: string[] = [];
  for (const [name, type, value] of [
    ["rooms", "gauge", lobby.rooms.size],
    ["guests_waiting", "gauge", lobby.guestCount()],
    ["connections", "gauge", sockets],
    ["rooms_created_total", "counter", lobby.stats.roomsCreated],
    ["joins_total", "counter", lobby.stats.joins],
    ["messages_total", "counter", lobby.stats.messages],
  ] as const) {
    lines.push(`# TYPE jotra_lobby_${name} ${type}`, `jotra_lobby_${name} ${value}`);
  }
  return lines.join("\n") + "\n";
}

if (import.meta.main) {
  const { server } = startServer(Number(process.env.PORT ?? 8080));
  console.log(`lobby listening on :${server.port}`);
}
