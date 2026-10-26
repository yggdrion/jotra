# Deploy: lobby and coturn (player host)

The player-host stack runs from a clone of this repo on the gvm host (`grafana.r4b2.de`,
Hetzner, 91.99.227.111) as its own compose project, in place of the retired Two Wards stack. gvm's Caddy (ports
80/443) terminates TLS for `jotra.r4b2.de` and proxies to the lobby, which also joins gvm's
network `gvm_default` as `jotra-lobby`. The game connects to `wss://jotra.r4b2.de/ws`
(`LobbyClient.DEFAULT_URL`; `--lobby=URL` picks another). DNS: an A record to the host, no
Cloudflare proxy, since TURN is UDP.

| Service | Public | Notes |
|---|---|---|
| `lobby` (built from `lobby/`) | `/ws`, `/healthz` through gvm's Caddy | `/metrics` stays internal |
| `coturn` | 3478 TCP/UDP, relay UDP 49160–49259 | credentials minted by the lobby from `TURN_SECRET` |

Shipping the lobby's and coturn's metrics to VictoriaMetrics comes with the vServer milestone (M10).

## First setup

Two Wards' lobby and coturn use the same ports and Caddy's attention, so stop them first
(`cd /root/two-wards/deploy && docker compose down`) and drop its `twowards.r4b2.de` Caddy block.

    cd /root && git clone https://github.com/yggdrion/jotra.git
    cd jotra/deploy/lobby
    cp .env.example .env && chmod 600 .env    # fill in TURN_SECRET
    docker compose up -d --build

The host firewall must let in 3478 TCP/UDP and UDP 49160–49259 (Two Wards opened 49160–49200). gvm's `Caddyfile` needs this
block (then `docker compose restart caddy` in `/root/gvm`):

```
jotra.r4b2.de {
    @public path /ws /healthz
    handle @public {
        reverse_proxy jotra-lobby:8080
    }
    respond 404
}
```

## Update

    cd /root/jotra && git pull && cd deploy/lobby && docker compose up -d --build

The lobby's message format has its own version (`PROTOCOL` in `lobby/src/server.ts`,
`LobbyClient.PROTOCOL` in the game), so game-only changes need no lobby redeploy.

## Check

    curl https://jotra.r4b2.de/healthz          # ok
    docker compose logs coturn --tail 20

A TURN credential for manual tests, minted the way the lobby does it:

    . ./.env; U="$(( $(date +%s) + 1800 )):check"
    P="$(printf %s "$U" | openssl dgst -sha1 -hmac "$TURN_SECRET" -binary | base64)"; echo "$U $P"
