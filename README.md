# Necesse Status Page

A self-hosted status page for a [Necesse](https://necessegame.com/) game server and its [Playit.gg](https://playit.gg) tunnel. It polls local health agents on each source LXC every minute, stores results in SQLite and serves a public status page via SvelteKit.

## Architecture

```
Necesse LXC   ── GET :9101/health──┐
                                   ├──► Status Page LXC ──► SQLite ──► SvelteKit (Node adapter)
Playit.gg LXC ── GET :9101/health──┘
```

Each **source LXC** runs a tiny Python health agent on `:9101/health`. The Necesse LXC reports `healthy` only when the service process is alive *and* its UDP socket is bound; the playit LXC reports `healthy` when `playit status` reports `Phase: running` (playit is an outbound tunnel client and never binds a local port). The status-page LXC does a plain HTTP `GET` against those agents, so it never has to deal with the fact that the real services are UDP.

## Install the LXC for Status page

Run the command below in the Proxmox VE Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/statuspage.sh)"
```

## Install a Health agent on a source LXC

Run the command below in each source LXC (the Necesse LXC and the playit LXC):

```bash
curl -fsSL -o /usr/local/bin/health-agent.py https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/health-agent/health-agent.py

curl -fsSL -o /etc/systemd/system/health-agent.service https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/health-agent/health-agent.service

chmod +x /usr/local/bin/health-agent.py
systemctl daemon-reload
systemctl enable --now health-agent
```

On the **Necesse LXC** nothing else is needed - the default
`port_and_process` mode checks the local UDP port + process.

On the **playit LXC**, run the one-shot setup script instead (it switches the agent to `playit` mode and installs the scoped sudo rule for `playit status`):

```bash
curl -fsSL -o /usr/local/bin/playit_user_setup.sh https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/scripts/playit_user_setup.sh

chmod +x /usr/local/bin/playit_user_setup.sh
/usr/local/bin/playit_user_setup.sh
```

The panel needs your agent URL in config.toml to correctly show when is active, and example could be like this:
```toml
[services]
NECESSE_HEALTH_URL="http://192.168.100.228:9101/health"
PLAYIT_HEALTH_URL="http://192.168.100.233:9101/health"
```

## Restart Health agent

If changes were made in `health-agent.py` or `health-agent.service`, execute this commands:
```bash
systemctl daemon-reload
systemctl restart health-agent
```

## Configure the status page

Target URLs are read from environment variables (see `deploy/status-page.service`):

| Variable | Default |
|---|---|
| `NECESSE_HEALTH_URL` | `http://192.168.100.228:9101/health` |
| `PLAYIT_HEALTH_URL` | `http://192.168.100.229:9101/health` |
| `STATUS_DB_PATH` | `/opt/status-page/data/status.db` |
| `PORT` | `3000` |

Change the playit target if its LXC IP changes. The public tunnel address
(`*.tun.ply.gg`) is display-only metadata and is intentionally *not* polled.

## Development

```bash
pnpm install    # install dependencies
pnpm dev        # run development mode
```

> NOTE: By default `status.db` is created in `/opt/status-page/data/` folder

```bash
pnpm build       # builds the production Node server into ./build
pnpm preview     # preview the production build
pnpm check       # typecheck with svelte-check
```

## Scripts

To clean DB rows for a recent configuration of status panel execute:
```bash
curl -fsSL -o /usr/local/bin/reset_db.sh https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/scripts/reset_db.sh

chmod +x /usr/local/bin/reset_db.sh
/usr/local/bin/reset_db.sh
```

In case your `SERVICE_URL` from your `health-agent.service` was updated, run the following script to update DB rows with correct service URL:
```bash
curl -fsSL -o /usr/local/bin/update_services_url.sh https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/scripts/update_services_url.sh

chmod +x /usr/local/bin/update_services_url.sh
/usr/local/bin/update_services_url.sh
```

## Exposing later

The status-page LXC only listens on `:3000` locally. You can create a `cloudflared` tunnel (hosted elsewhere) at `http://<status-lxc-ip>:3000` and map it to `status.website.com`.

## Notes

- The poll runs in-process via `node-cron` and stores ~1M rows/year for 2 services.
  Prune old rows if you want to keep the DB small: 
  `DELETE FROM checks WHERE checked_at < strftime('%s','now')*1000 - 7776000000;`
- Checks run concurrently (`Promise.allSettled`) with a 5s per-request timeout to keep minute-to-minute drift minimal.
