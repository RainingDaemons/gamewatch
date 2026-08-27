# GameWatch - Customizable Status Panel for your Game Services

A self-hosted status page for your game servers and its [Playit.gg](https://playit.gg) tunnel. It polls local health agents on each source LXC every minute, stores results in SQLite and serves a public status page via SvelteKit.

## Architecture

```
Gameserver LXC   ── GET :9101/health──┐
                                   ├──► Status Page LXC ──► SQLite ──► SvelteKit (Node adapter)
Playit.gg LXC ── GET :9101/health──┘
```

Each **source LXC** runs a tiny Python health agent on `:9101/health`. The Gameserver LXC reports `healthy` only when the service process is alive *and* its UDP socket is bound; the playit LXC reports `healthy` when `playit status` reports `Phase: running` (playit is an outbound tunnel client and never binds a local port). The status-page LXC does a plain HTTP `GET` against those agents, so it never has to deal with the fact that the real services are UDP.

## Install the LXC for Status page

Run the command below in the Proxmox VE Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/statuspage.sh)"
```

## Install a Health agent on a source LXC

Run the command below in each source LXC (the Gameserver LXC and the playit LXC):

```bash
curl -fsSL -o /usr/local/bin/health-agent.py https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/health-agent/health-agent.py

curl -fsSL -o /etc/systemd/system/health-agent.service https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/health-agent/health-agent.service

chmod +x /usr/local/bin/health-agent.py
systemctl daemon-reload
systemctl enable --now health-agent
```

Inside the **Gameserver LXC** create the following rule to the status panel can reach the service:
```bash
ufw allow from ip-status-panel to any port 9101 proto tcp
```

> NOTA: Replace `ip-status-panel` with `hostname -I` ip from Status Page LXC

On the **Playit LXC**, run the one-shot setup script instead (it switches the agent to `playit` mode and installs the scoped sudo rule for `playit status`):

```bash
curl -fsSL -o /usr/local/bin/playit_user_setup.sh https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/scripts/playit_user_setup.sh

chmod +x /usr/local/bin/playit_user_setup.sh
/usr/local/bin/playit_user_setup.sh
```

## Restart Health agent

If changes were made in `health-agent.py` or `health-agent.service`, execute this commands:
```bash
systemctl daemon-reload
systemctl restart health-agent
```

## Configure the status page

Environment variables read by the app:

| Variable | Default |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | `3000` |
| `STATUS_DB_PATH` | `/opt/status-page/data/status.db` |
| `STATUS_CONFIG_PATH` | `./config.toml` |

The service URLs are configured in `config.toml` (the source of truth), e.g.:
```toml
services = [
  { name = "necesse", display_name = "Necesse Service", health_url = "http://192.168.100.228:9101/health", extra_pages = yes },
  { name = "playit", display_name = "Playit.gg Tunnel", health_url = "http://192.168.100.233:9101/health", extra_pages = false }
]

```

## Extra info pages

Set `extra_pages = yes` on a service to turn its display name into a link. The
link points to `/info/<name>` (e.g. `https://status.website.com/info/necesse`).

The page content lives in a folder at the repo root:

```
extra_pages/
  +layout.svelte # generic layout: back-to-home button + "<display_name> Info" title
  necesse/
    +page.svelte # content rendered at /info/necesse
```

Only services with `extra_pages = yes` are linked. Extra pages are rendered
client-side (CSR), so you can fetch dynamic content inside them on mount.

## Check DB backup service

A `backup.service` deamon is created with a `backup.timer` to every check check olds rows from DB and delete it and save a last-weeek DB backup, check if timer is set properly with:
```bash
systemctl daemon-reload
systemctl status backup.timer
systemctl list-timers backup.timer
```

If you want to test if backup service is working execute this commands:
```bash
systemctl start backup.service
systemctl status backup.service
```

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
curl -fsSL -o /usr/local/bin/reset_db.sh https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/scripts/reset_db.sh

chmod +x /usr/local/bin/reset_db.sh
/usr/local/bin/reset_db.sh
```

In case your `config.toml` was changed, run the following script to update DB rows with correct services URL:
```bash
curl -fsSL -o /usr/local/bin/update_services_url.sh https://raw.githubusercontent.com/RainingDaemons/gamewatch/main/scripts/update_services_url.sh

chmod +x /usr/local/bin/update_services_url.sh
/usr/local/bin/update_services_url.sh
```

## Exposing later

The status-page LXC only listens on `:3000` locally. You can create a `cloudflared` tunnel (hosted elsewhere) at `http://<status-lxc-ip>:3000` and map it to `status.website.com`.

## Notes

- Checks run concurrently (`Promise.allSettled`) with a 5s per-request timeout to keep minute-to-minute drift minimal.
