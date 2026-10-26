# Deploy: lobby and coturn (player host)

The player-host stack runs from a clone of this repo on the gvm host (`grafana.r4b2.de`,
Hetzner, 91.99.227.111) as its own compose project, where the retired Two Wards stack ran. gvm's Caddy (ports
80/443) terminates TLS for `lobby.r4b2.de` and proxies to the lobby, which also joins gvm's
network `gvm_default` as `jotra-lobby`. The game connects to `wss://lobby.r4b2.de/ws`
(`LobbyClient.DEFAULT_URL`; `--lobby=URL` picks another). DNS: an A record to the host, no
Cloudflare proxy, since TURN is UDP.

| Service | Public | Notes |
|---|---|---|
| `lobby` (built from `lobby/`) | `/ws`, `/healthz` through gvm's Caddy | `/metrics` stays internal |
| `coturn` | 3478 TCP/UDP, relay UDP 49160–49259 | credentials minted by the lobby from `TURN_SECRET` |

Shipping the lobby's and coturn's metrics to VictoriaMetrics comes with the vServer milestone (M10).

## First setup

    cd /root && git clone https://github.com/yggdrion/jotra.git
    cd jotra/deploy/lobby
    cp .env.example .env && chmod 600 .env    # fill in TURN_SECRET
    docker compose up -d --build

The host firewall must let in 3478 TCP/UDP and UDP 49160–49259. gvm's `Caddyfile` (repo
`yggdrion/gvm`) routes `lobby.r4b2.de` to `jotra-lobby:8080`, only `/ws` and `/healthz`; after
changing it, `cd /root/gvm && git pull && docker compose restart caddy`.

## Update

    cd /root/jotra && git pull && cd deploy/lobby && docker compose up -d --build

The lobby's message format has its own version (`PROTOCOL` in `lobby/src/server.ts`,
`LobbyClient.PROTOCOL` in the game), so game-only changes need no lobby redeploy.

## Check

    curl https://lobby.r4b2.de/healthz          # ok
    docker compose logs coturn --tail 20

A TURN credential for manual tests, minted the way the lobby does it:

    . ./.env; U="$(( $(date +%s) + 1800 )):check"
    P="$(printf %s "$U" | openssl dgst -sha1 -hmac "$TURN_SECRET" -binary | base64)"; echo "$U $P"
