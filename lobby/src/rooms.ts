// Rooms and signaling relay, without sockets so tests can drive it directly.
//
// A room belongs to one game server (the "host" here; GameServer in the game, started by the
// player who hosts). It stays open while that server runs and pings, so friends can join at
// any time. Every guest connects to the server only (star topology): the server is WebRTC peer
// 1 and each guest gets the next id in its room, which the game uses as its peer id.
//
// Client -> lobby (JSON):
//   {type: "host", protocol}            a game server opens a room
//   {type: "join", code, protocol}      a player joins by code
//   {type: "signal", to?, data}         WebRTC offer/answer/candidate, relayed verbatim; the
//                                       host names the guest id, a guest always reaches the host
//   {type: "ping"}                      the host's heartbeat; keeps its room open
// Lobby -> client:
//   {type: "hosted", code, ice}         {type: "joined", code, id, ice}
//   {type: "guest", id}                 to the host: a guest is waiting for its offer
//   {type: "left", id}                  to the host: a guest's socket closed
//   {type: "signal", from, data}        {type: "pong"}       {type: "error", reason}
//
// The lobby never looks inside "signal" data and never sees gameplay. Guests close their socket
// once connected; the host keeps its socket for as long as the room is open.

import { createHmac } from "node:crypto";

export interface Peer {
  send(message: string): void;
}

export interface IceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

export interface Config {
  // Must match LobbyClient.PROTOCOL in the game.
  protocol: number;
  // coturn host for STUN/TURN; empty disables both (local tests).
  turnHost: string;
  turnPort: number;
  // coturn static-auth-secret; empty means STUN only.
  turnSecret: string;
  // How long TURN credentials stay valid.
  turnTtlSeconds: number;
  // A room whose host has not pinged for this long is dropped.
  roomTimeoutMs: number;
  // A guest still in the lobby after this long is dropped (it never got through).
  guestTimeoutMs: number;
  // Guests waiting in one room at once. The game server caps the players in the world.
  maxGuests: number;
}

interface Guest {
  id: number;
  peer: Peer;
  joinedAt: number;
}

interface Room {
  code: string;
  host: Peer;
  lastPing: number;
  nextId: number;
  guests: Map<number, Guest>;
}

// No 0/O, 1/I/L, so codes survive being read out loud.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LENGTH = 4;
// Peer id 1 is the game server.
const FIRST_GUEST_ID = 2;

export class Lobby {
  readonly rooms = new Map<string, Room>();
  readonly stats = { roomsCreated: 0, joins: 0, messages: 0 };
  // Which room a socket is in, and as which guest (0 for the host).
  private readonly byPeer = new Map<Peer, { room: Room; id: number }>();

  constructor(
    private readonly config: Config,
    private readonly now: () => number = Date.now,
    private readonly random: () => number = Math.random,
  ) {}

  guestCount(): number {
    let count = 0;
    for (const room of this.rooms.values()) count += room.guests.size;
    return count;
  }

  handle(peer: Peer, raw: string): void {
    this.stats.messages++;
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw);
    } catch {
      return send(peer, { type: "error", reason: "bad message" });
    }
    if (typeof msg !== "object" || msg === null) {
      return send(peer, { type: "error", reason: "bad message" });
    }
    switch (msg.type) {
      case "host":
        return this.host(peer, msg.protocol);
      case "join":
        return this.join(peer, String(msg.code ?? "").toUpperCase(), msg.protocol);
      case "signal":
        return this.signal(peer, msg.to, msg.data);
      case "ping": {
        const entry = this.byPeer.get(peer);
        if (entry && entry.id === 0) entry.room.lastPing = this.now();
        return send(peer, { type: "pong" });
      }
      default:
        return send(peer, { type: "error", reason: "bad message" });
    }
  }

  // The peer's socket closed. A host's room closes with it; a guest just leaves its room.
  leave(peer: Peer): void {
    const entry = this.byPeer.get(peer);
    if (!entry) return;
    if (entry.id === 0) {
      this.close(entry.room, "the host closed the room");
    } else {
      this.dropGuest(entry.room, entry.id);
    }
  }

  // Drops rooms whose host stopped pinging and guests that never got through; the server calls
  // this on a timer.
  sweep(): void {
    const now = this.now();
    for (const room of this.rooms.values()) {
      if (room.lastPing < now - this.config.roomTimeoutMs) {
        send(room.host, { type: "error", reason: "room timed out" });
        this.close(room, "the room timed out");
        continue;
      }
      for (const guest of room.guests.values()) {
        if (guest.joinedAt >= now - this.config.guestTimeoutMs) continue;
        send(guest.peer, { type: "error", reason: "could not reach the host in time" });
        this.dropGuest(room, guest.id);
      }
    }
  }

  // ICE servers for one room, with coturn REST credentials (username "expiry:code").
  iceServers(code: string): IceServer[] {
    const { turnHost, turnPort, turnSecret, turnTtlSeconds } = this.config;
    if (!turnHost) return [];
    const address = `${turnHost}:${turnPort}`;
    const servers: IceServer[] = [{ urls: [`stun:${address}`] }];
    if (turnSecret) {
      const username = `${Math.floor(this.now() / 1000) + turnTtlSeconds}:${code}`;
      const credential = createHmac("sha1", turnSecret).update(username).digest("base64");
      servers.push({
        urls: [`turn:${address}?transport=udp`, `turn:${address}?transport=tcp`],
        username,
        credential,
      });
    }
    return servers;
  }

  private host(peer: Peer, protocol: unknown): void {
    if (!this.checkProtocol(peer, protocol)) return;
    if (this.byPeer.has(peer)) return send(peer, { type: "error", reason: "already in a room" });
    let code = this.newCode();
    // Retries on collision; fine while rooms are far fewer than 23^4 = 279841.
    while (this.rooms.has(code)) code = this.newCode();
    const room: Room = {
      code,
      host: peer,
      lastPing: this.now(),
      nextId: FIRST_GUEST_ID,
      guests: new Map(),
    };
    this.rooms.set(code, room);
    this.byPeer.set(peer, { room, id: 0 });
    this.stats.roomsCreated++;
    send(peer, { type: "hosted", code, ice: this.iceServers(code) });
  }

  private join(peer: Peer, code: string, protocol: unknown): void {
    if (!this.checkProtocol(peer, protocol)) return;
    if (this.byPeer.has(peer)) return send(peer, { type: "error", reason: "already in a room" });
    const room = this.rooms.get(code);
    if (!room) return send(peer, { type: "error", reason: "no room with that code" });
    if (room.guests.size >= this.config.maxGuests) {
      return send(peer, { type: "error", reason: "too many players joining at once" });
    }
    const id = room.nextId++;
    room.guests.set(id, { id, peer, joinedAt: this.now() });
    this.byPeer.set(peer, { room, id });
    this.stats.joins++;
    send(peer, { type: "joined", code, id, ice: this.iceServers(code) });
    send(room.host, { type: "guest", id });
  }

  private signal(peer: Peer, to: unknown, data: unknown): void {
    const entry = this.byPeer.get(peer);
    if (!entry) return;
    const { room, id } = entry;
    if (id !== 0) return send(room.host, { type: "signal", from: id, data });
    const guest = room.guests.get(Number(to));
    if (guest) send(guest.peer, { type: "signal", from: 1, data });
  }

  private checkProtocol(peer: Peer, protocol: unknown): boolean {
    if (Number(protocol) === this.config.protocol) return true;
    send(peer, { type: "error", reason: "game version does not match the lobby" });
    return false;
  }

  private dropGuest(room: Room, id: number): void {
    const guest = room.guests.get(id);
    if (!guest) return;
    room.guests.delete(id);
    this.byPeer.delete(guest.peer);
    send(room.host, { type: "left", id });
  }

  // Removes the room; guests still waiting hear why.
  private close(room: Room, reason: string): void {
    this.rooms.delete(room.code);
    this.byPeer.delete(room.host);
    for (const guest of room.guests.values()) {
      this.byPeer.delete(guest.peer);
      send(guest.peer, { type: "error", reason });
    }
  }

  private newCode(): string {
    let code = "";
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += ALPHABET[Math.floor(this.random() * ALPHABET.length)];
    }
    return code;
  }
}

function send(peer: Peer, msg: object): void {
  peer.send(JSON.stringify(msg));
}
