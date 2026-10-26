import { describe, expect, test } from "bun:test";
import { createHmac } from "node:crypto";
import { Lobby, type Config, type Peer } from "./rooms";
import { PROTOCOL, startServer } from "./server";

class FakePeer implements Peer {
  inbox: Record<string, unknown>[] = [];
  send(message: string) {
    this.inbox.push(JSON.parse(message));
  }
  last() {
    return this.inbox[this.inbox.length - 1];
  }
}

const config: Config = {
  protocol: 1,
  turnHost: "turn.example",
  turnPort: 3479,
  turnSecret: "s3cret",
  turnTtlSeconds: 3600,
  roomTimeoutMs: 60_000,
  guestTimeoutMs: 120_000,
  maxGuests: 3,
};

function setup(now = () => 1_000_000) {
  const lobby = new Lobby(config, now);
  const host = new FakePeer();
  lobby.handle(host, JSON.stringify({ type: "host", protocol: 1 }));
  const code = host.last().code as string;
  const join = (as_code = code) => {
    const guest = new FakePeer();
    lobby.handle(guest, JSON.stringify({ type: "join", code: as_code, protocol: 1 }));
    return guest;
  };
  return { lobby, host, code, join };
}

describe("rooms", () => {
  test("host gives a 4-letter code and ICE servers", () => {
    const { lobby, host, code } = setup();
    expect(code).toMatch(/^[A-HJKMNP-Z]{4}$/);
    expect(host.last().type).toBe("hosted");
    expect(host.last().ice).toHaveLength(2);
    expect(lobby.rooms.size).toBe(1);
  });

  test("guests get their own peer ids from 2 up, case-insensitive codes", () => {
    const { host, code, join } = setup();
    const a = join(code.toLowerCase());
    expect(a.last()).toMatchObject({ type: "joined", code, id: 2 });
    expect(host.last()).toEqual({ type: "guest", id: 2 });
    const b = join();
    expect(b.last()).toMatchObject({ type: "joined", id: 3 });
    expect(host.last()).toEqual({ type: "guest", id: 3 });
  });

  test("signals go from the host to the named guest and from guests to the host", () => {
    const { lobby, host, join } = setup();
    const a = join();
    const b = join();
    const offer = { kind: "offer", sdp: "v=0..." };
    lobby.handle(host, JSON.stringify({ type: "signal", to: 3, data: offer }));
    expect(b.last()).toEqual({ type: "signal", from: 1, data: offer });
    expect(a.last().type).toBe("joined");
    lobby.handle(a, JSON.stringify({ type: "signal", to: 3, data: { kind: "candidate" } }));
    expect(host.last()).toEqual({ type: "signal", from: 2, data: { kind: "candidate" } });
    expect(b.last()).toEqual({ type: "signal", from: 1, data: offer });
  });

  test("unknown code, a crowded room and a wrong version are refused", () => {
    const { lobby, join } = setup();
    expect(join("ZZZZ").last()).toMatchObject({ type: "error", reason: "no room with that code" });
    join();
    join();
    join();
    expect(join().last()).toMatchObject({ type: "error", reason: "too many players joining at once" });
    const old = new FakePeer();
    lobby.handle(old, JSON.stringify({ type: "host", protocol: 0 }));
    expect(old.last().type).toBe("error");
    lobby.handle(old, "not json");
    expect(old.last()).toMatchObject({ type: "error", reason: "bad message" });
  });

  test("a guest leaving tells the host and frees its place; ids are not reused", () => {
    const { lobby, host, join } = setup();
    const a = join();
    lobby.leave(a);
    expect(host.last()).toEqual({ type: "left", id: 2 });
    expect(lobby.guestCount()).toBe(0);
    expect(join().last()).toMatchObject({ type: "joined", id: 3 });
    expect(lobby.rooms.size).toBe(1);
  });

  test("the room closes with its host and tells waiting guests", () => {
    const { lobby, host, join } = setup();
    const a = join();
    lobby.leave(host);
    expect(lobby.rooms.size).toBe(0);
    expect(a.last()).toMatchObject({ type: "error", reason: "the host closed the room" });
    lobby.handle(a, JSON.stringify({ type: "signal", data: {} }));
    expect(host.last().type).toBe("guest");
  });

  test("pings keep a room open as long as its server runs", () => {
    let now = 1_000_000;
    const { lobby, host } = setup(() => now);
    for (let i = 0; i < 10; i++) {
      now += config.roomTimeoutMs - 1;
      lobby.handle(host, JSON.stringify({ type: "ping" }));
      expect(host.last()).toEqual({ type: "pong" });
      lobby.sweep();
    }
    expect(lobby.rooms.size).toBe(1);
    now += config.roomTimeoutMs + 1;
    lobby.sweep();
    expect(lobby.rooms.size).toBe(0);
    expect(host.last()).toMatchObject({ type: "error", reason: "room timed out" });
  });

  test("a guest's ping does not keep the room open", () => {
    let now = 1_000_000;
    const { lobby, join } = setup(() => now);
    const a = join();
    now += config.roomTimeoutMs + 1;
    lobby.handle(a, JSON.stringify({ type: "ping" }));
    lobby.sweep();
    expect(lobby.rooms.size).toBe(0);
  });

  test("guests that never get through are dropped", () => {
    let now = 1_000_000;
    const { lobby, host, join } = setup(() => now);
    const a = join();
    now += config.guestTimeoutMs + 1;
    lobby.handle(host, JSON.stringify({ type: "ping" }));
    lobby.sweep();
    expect(a.last()).toMatchObject({ type: "error" });
    expect(host.last()).toEqual({ type: "left", id: 2 });
    expect(lobby.rooms.size).toBe(1);
  });

  test("TURN credentials follow the coturn REST scheme", () => {
    const { lobby } = setup();
    const [stun, turn] = lobby.iceServers("ABCD");
    expect(stun.urls).toEqual(["stun:turn.example:3479"]);
    expect(turn.username).toBe(`${1000 + 3600}:ABCD`);
    expect(turn.credential).toBe(
      createHmac("sha1", "s3cret").update(turn.username!).digest("base64"),
    );
    expect(new Lobby({ ...config, turnHost: "" }).iceServers("ABCD")).toEqual([]);
    expect(new Lobby({ ...config, turnSecret: "" }).iceServers("ABCD")).toHaveLength(1);
  });
});

describe("server", () => {
  test("a host and two guests signal through websockets, metrics count them", async () => {
    const { server, stop } = startServer(0, { turnHost: "" });
    const url = `ws://127.0.0.1:${server.port}/ws`;
    const connect = async () => {
      const ws = new WebSocket(url);
      const inbox: Record<string, unknown>[] = [];
      const waiting: ((m: Record<string, unknown>) => void)[] = [];
      ws.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        const resolve = waiting.shift();
        if (resolve) resolve(msg);
        else inbox.push(msg);
      };
      await new Promise((r) => (ws.onopen = r));
      const next = () =>
        inbox.length > 0
          ? Promise.resolve(inbox.shift()!)
          : new Promise<Record<string, unknown>>((r) => waiting.push(r));
      return { ws, next, send: (msg: object) => ws.send(JSON.stringify(msg)) };
    };
    const host = await connect();
    host.send({ type: "host", protocol: PROTOCOL });
    const hosted = await host.next();
    expect(hosted.ice).toEqual([]);
    const a = await connect();
    a.send({ type: "join", code: hosted.code, protocol: PROTOCOL });
    expect(await a.next()).toMatchObject({ type: "joined", id: 2 });
    expect(await host.next()).toEqual({ type: "guest", id: 2 });
    const b = await connect();
    b.send({ type: "join", code: hosted.code, protocol: PROTOCOL });
    expect(await b.next()).toMatchObject({ type: "joined", id: 3 });
    expect(await host.next()).toEqual({ type: "guest", id: 3 });
    host.send({ type: "signal", to: 3, data: { kind: "offer" } });
    expect(await b.next()).toEqual({ type: "signal", from: 1, data: { kind: "offer" } });
    a.send({ type: "signal", data: { kind: "answer" } });
    expect(await host.next()).toEqual({ type: "signal", from: 2, data: { kind: "answer" } });
    const metrics = await (await fetch(`http://127.0.0.1:${server.port}/metrics`)).text();
    expect(metrics).toContain("jotra_lobby_rooms 1");
    expect(metrics).toContain("jotra_lobby_guests_waiting 2");
    expect(metrics).toContain("jotra_lobby_connections 3");
    expect(await (await fetch(`http://127.0.0.1:${server.port}/healthz`)).text()).toBe("ok");
    a.ws.close();
    expect(await host.next()).toEqual({ type: "left", id: 2 });
    host.ws.close();
    b.ws.close();
    stop();
  });
});
