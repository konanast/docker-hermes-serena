# Hermes + Serena on Raspberry Pi 5 (ARM64)

Two services, one shared workspace, your existing Open WebUI and LAN model server.
Verified against official source and live registry ARM64 manifests on **2026-09-23**.
Read `VERIFICATION.md` for precise evidence and testing limits. This bundle is prepared
for deployment; it has **not been run on a Raspberry Pi or in Docker here**.

Open WebUI → `http://hermes:8642/v1` → Hermes agent → LAN model server.
Hermes calls Serena at **`http://serena:9121/mcp`**. Both use the same
`./workspace` bind mount at `/workspace`. Neither contains a model server.

## Requirements

- Raspberry Pi OS **64-bit** or another ARM64 Linux; `uname -m` should say `aarch64`.
- Docker Engine with Compose v2 supporting `up --wait`, Bash, Python 3,
  `tar`, `flock` (util-linux), sufficient free disk and access to both registries.
- Existing external Docker network `lab`, with your existing Open WebUI attached.
  Check with `docker network inspect lab`. The bundle deliberately does not create it.
- A LAN OpenAI-compatible chat-completions server and a model supporting **tool calling**.
  Use the machine's LAN IP/DNS, not `localhost`. Include `/v1` when required by that server.
- Images are large (Hermes upstream notes 5 GB+); allow extra disk for layers,
  rollback images and backups. SSD storage and an 8 GB+ Pi are sensible starting points,
  not a tested minimum. The language server consumes RAM on the Pi, even with remote inference.

## Initialize and start

Extract the ZIP into a new directory. Do not extract over an existing deployment.
Run as the host user who owns the projects (use `sudo` for Docker installation, not initialization).

```bash
cd hermes-serena-pi
bash scripts/init.sh
nano .env
# Set MODEL_BASE_URL, MODEL_NAME and MODEL_API_KEY.
# If the LAN server has no authentication, leave MODEL_API_KEY=local-no-auth.
bash scripts/up.sh
bash scripts/health.sh
```

`init.sh` generates a random 256-bit **HERMES_API_KEY**, sets PUID/PGID to your host IDs,
creates private state directories, and copies configuration templates only when absent.
It never changes an existing `.env`, secret, configuration or project file. An existing
`.env` with an empty API key needs manual correction (`openssl rand -hex 32`). Do not
paste secrets into chat or commit `.env`, state or backups to Git.

`up.sh` pulls Hermes and builds a small Serena derivative from the latest official image.
It preserves the official Hermes bootstrap; the gateway drops privileges to your UID/GID.
Serena runs with the same UID/GID. The derivative relocates upstream's Node installation
from `/root/.nvm` to `/opt/serena-node` and exposes uv/uvx under `/usr/local/bin`
so the unprivileged Python language server can use them.
No Docker socket, host root mount or privileged mode is used. No source checkout is needed.

Persistent files:

| Host path | Container path | Purpose |
|---|---|---|
| `state/hermes/` | Hermes `/opt/data` | Config, credentials, sessions, memory, logs, skills |
| `state/serena/` | Serena `/state` | Home, caches and `.serena/serena_config.yml` |
| `workspace/` | Both `/workspace` | Projects and project-local `.serena` memories/indexes |
| `.env` | Explicit environment mappings | Model settings, IDs and API key |

Edit active configs under `state/`, not the seed templates under `config/`.
Model settings remain configurable through `.env` using Hermes's supported `${VAR}`
expansion in `config.yaml`. Apply changes with `docker compose up -d --force-recreate`
(no image update is needed). If a config migration replaces these references, restore
them explicitly or maintain model settings directly in the active config.

## Connect existing Open WebUI

In your existing Open WebUI admin settings, add an **OpenAI-compatible connection**:

- URL: **`http://hermes:8642/v1`**
- API key: the generated **HERMES_API_KEY** from this bundle's `.env`
- Choose **`hermes-agent`** in the model picker. This is the API alias, independent of MODEL_NAME.

Do not point this connection directly at the LAN model server. Hermes performs the agent
loop and calls Serena on the server side. Its `platform_toolsets.api_server` explicitly
includes `terminal`, `file` and `serena`; configuring CLI toolsets alone is insufficient.
Do not add Serena as a separate Open WebUI tool connection for this test. No CORS setting
is required for the normal server-to-server connection. Existing Open WebUI connections
can remain in place. Set a sufficiently long Open WebUI/proxy request timeout for slow
Pi indexing or tool turns (for example 300 seconds).

## Daily operations

Run all commands from this directory:

```bash
docker compose stop                         # stop both, preserve containers and data
docker compose start                        # restart existing containers
# Create/start from already prepared images:
docker compose up -d --no-build --wait --wait-timeout 300
docker compose logs -f --tail=100 hermes
docker compose logs -f --tail=100 serena
docker compose ps
bash scripts/health.sh
docker compose down                         # remove containers; bind-mounted data stays
```

`health.sh` checks MCP initialization/tool discovery, Hermes liveness, models/toolsets
and LAN `/models` reachability. Some compatible servers lack `/models`; in that case
check a chat request instead. A healthy container does not prove that the model calls
tools correctly, that a language server works, or that an entire chat turn succeeds.

## Verify shared files and semantic tools

The sample project is `/workspace/projects/my-project`, containing `calculator.py`.
Check that both containers see identical bytes:

```bash
docker compose exec -T hermes sha256sum /workspace/projects/my-project/calculator.py
docker compose exec -T serena sha256sum /workspace/projects/my-project/calculator.py
# Explicit MCP test from Serena's environment, with its own DNS name:
docker compose exec -T serena /workspaces/serena/.venv/bin/python - < scripts/smoke-serena.py
```

The last command activates the sample project and starts its Python language server;
it may download dependencies on first use. It should report Calculator, add and main.
A normal MCP health check never activates a project. Test these prompts in a **new
Open WebUI chat with hermes-agent**:

1. “First call Serena initial_instructions, read its instructions and retain the returned
   session ID. Pass that session_id to tools that require it. Use Serena's activate_project tool to activate /workspace/projects/my-project.
   Then use get_current_config to report the active project. Show the actual tool
   results; do not infer success.”
2. “Use Serena get_symbols_overview on calculator.py with depth 1. Then use
   find_symbol for Calculator/add with include_body true. Report the signature and body.”
3. “Use Serena find_referencing_symbols for Calculator/add in calculator.py.
   Then use the Hermes terminal to run pwd and python /workspace/projects/my-project/calculator.py.
   Expected working directory is /workspace and output is 5.”
4. Optional write test: “Use the Hermes terminal to write shared-check.txt under
   /workspace/projects/my-project with the text shared-ok. Read it with Serena read_file.”

Hermes may prefix displayed tool names with the MCP server name. The underlying tools
should be called, not merely described in the answer. Check both services' logs.
The bundled Serena context is `desktop-app`, with the standard individual tool
interface. Serena's active project is shared server state: treat this deployment as a
single trusted operator/project context. Concurrent chats switching projects can interfere.
Open WebUI users with this connection share powerful workspace access, not separate sandboxes.

## Latest versions and coordinated updates

Defaults are `nousresearch/hermes-agent:latest` and `ghcr.io/oraios/serena:latest`.
These track **latest published main-branch images**, not necessarily stable releases;
Serena's checked source identifies itself as `2.0.0.dev0`. Publication can lag a commit.
To freeze versions, use digest references in `.env`. The update script honors pins.
It updates only container software, never rewrites your configs or rotates your keys.

```bash
bash scripts/update.sh           # both (same as all)
bash scripts/update.sh hermes    # only Hermes image
bash scripts/update.sh serena    # only Serena image
```

The script requires existing containers for rollback. It locks against concurrent
updates, tags both old images, prepares selected new images, stops **both services**,
and archives `.env`, all state and the entire workspace to `backups/<timestamp>/data.tar.gz`.
Then it recreates selected services, restarts both to refresh MCP sessions and runs health
checks. Single-service updates still pause both for a consistent snapshot. Allow space
for the entire workspace; large projects make backups slower. Pause any external editor
or process writing that workspace during the snapshot. User data is retained, but upstream
applications can perform schema migrations when they start. Keep backups until verified.

The script stops on failure and reports its backup path; it does not automatically roll
back possibly migrated data. New containers can remain running after a failed health
check. Stop both before restoring. Do not use `hermes update` inside the container.
`versions/` records image identities after successful updates. Keep rollback image tags;
`docker image prune -a` can remove images required for recovery.

### Rollback after a failed update

Set B to the actual backup directory; first confirm `data.tar.gz` exists and is readable.
If preparation failed before the snapshot, original containers/state are still in place;
do not attempt a data restore from a missing archive.

```bash
B=backups/REPLACE_WITH_TIMESTAMP
 tar -tzf "$B/data.tar.gz" >/dev/null
docker compose stop
# Keep failed state for investigation; do not merge old SQLite files into new state.
mkdir -p "$B/failed-state"
mv state workspace "$B/failed-state/"
cp .env "$B/failed-state/env"
tar -xzf "$B/data.tar.gz"
# Default, network-only deployment:
docker compose -f docker-compose.yml -f "$B/rollback.json" up -d --no-build --pull never --wait --wait-timeout 300
```

For the LAN option, insert `-f docker-compose.lan.yml` **before** `-f "$B/rollback.json"`.
The override uses the saved local image tags for both services. Continue using this
override until you deliberately fix/retry the update or set pinned image references;
a plain `up` without it may select the newer images again. Backups contain credentials.
Copy them securely off the Pi for disk-failure recovery.

## Optional LAN access to Hermes API

Default Compose publishes **no host ports**. Set HERMES_LAN_IP to the Pi's specific LAN
address in `.env`. To persist the override across scripts and updates, uncomment:

```dotenv
COMPOSE_FILE=docker-compose.yml:docker-compose.lan.yml
```

Then `docker compose up -d --no-build`. The API is available at
`http://PI_LAN_IP:8642/v1`, protected by HERMES_API_KEY. Open WebUI on `lab` continues
using `http://hermes:8642/v1`. The override does not expose Serena or any dashboard.
For a one-off invocation use both `-f` files explicitly, but remember to repeat them
for later operations. LAN HTTP carries tokens in plaintext; use a trusted LAN or a
TLS reverse proxy for remote access. Neither dashboard is included as an enabled option.

## Integrations and network access

No Telegram, Discord, Nous Portal or other cloud/messaging integration is configured.
A fresh state directory contains no login tokens for them. This is **not an outbound
firewall**: `lab` ordinarily allows egress; model calls, dependency downloads, update
checks, MCP tools and terminal commands can make network requests. No Portal subscription
is required for this LAN model + local tools setup. To enforce LAN-only egress, configure
host/router firewall rules for your Docker subnet while allowing the model server and DNS;
allow registry/package access when installing or updating. Do not make `lab` internal
blindly because existing Open WebUI may depend on its routing.

Later you can deliberately add credentials/config under the active Hermes state and enable
additional platform toolsets/integrations, then restart Hermes. Review upstream documentation
and any inbound port needs first. Do not import messaging tokens unintentionally during migration.
All containers on `lab` can reach Serena's unauthenticated MCP port: only trusted workloads
should join that network. The Hermes API key grants terminal and file capabilities inside
its container and its bind mounts; it is not merely a model inference token.

## Migration from existing installations

Do not modify your original installations until the new copy passes the checks above.
Never run two Hermes processes against the same SQLite state. Do not recursively copy the
old program checkout or a Python venv over either image's application directory.

1. Record old versions, storage paths, startup commands, environment settings and service
   owners. Stop old Hermes and Serena cleanly. Disable their automatic restart while migrating.
   Back up their full state and every project's `.serena` directory, including hidden files.
   Save credentials separately with restrictive permissions. A Docker-managed volume in the
   old deployment can be copied out with `docker cp OLD_CONTAINER:/actual/path/. ./staging/`;
   inspect old mounts first. Do not delete old containers/volumes.
2. Extract this bundle to a **new** directory and initialize it. Stage old data outside
   `state/`, e.g. `migration-staging/hermes` and `migration-staging/serena`. For a typical
   host install copy `~/.hermes/.` and `~/.serena/.` respectively (`cp -a` preserves dotfiles).
   Paths may differ; official Hermes Docker state is `/opt/data`, while older/custom images
   may differ. This bundle's Serena global home is `state/serena/.serena`.
3. Compare the staged configs with `state/hermes/config.yaml` and
   `state/serena/.serena/serena_config.yml`. **Merge manually**. Preserve sessions/databases,
   memories, skills and credentials; use `cp -an` or `rsync -a --ignore-existing` for an
   initial non-overwriting data copy, then review skipped conflicts explicitly. Never run
   an unconditional copy/rsync over the active configuration. Keep an untouched original
   backup so no skipped config or credential is lost.
4. Preserve Hermes `auth.json`, `.env`, credential pools and profile data in the staging
   backup. Import only intended provider credentials into the active installation. An old
   `.env` can automatically enable messaging; old profiles can automatically launch more
   gateways via Hermes's container supervisor. Do **not** copy old `.env`, `profiles/`,
   integration configs or cron schedules wholesale into the running home. Review and import
   them individually, keeping messaging/platforms disabled for this deployment. Keep the
   old credentials in the private backup for later opt-in. If reusing your old Hermes API
   key intentionally, set it in the bundle `.env`; otherwise use the new generated key.
5. In Hermes keep `provider: custom`, the LAN URL/model/key, `terminal.backend: local`,
   `terminal.cwd: /workspace`, the `mcp_servers.serena.url`, and the `api_server` toolset
   entries from the template. Remove obsolete Serena stdio commands or localhost URLs.
   Review fallback/auxiliary model providers, plugins and credential routing so imported
   settings do not send requests to old cloud providers. Do not import Portal setup as active.
6. Copy your actual projects under `workspace/projects/`, preserving their project-local
   `.serena/` memories/config. The bundled `my-project` is only a fixture: move it aside
   before bringing in a real project of that name. Replace old absolute paths in Serena's
   global project list with `/workspace/projects/...`; review absolute paths in project configs,
   memories and scripts. Activate by the new absolute path. Old LSP caches may contain host
   paths; back them up and rebuild indexes instead of deleting memories. Existing project
   configurations may use older language keys; consult the current official project template.
7. Ensure the copied `state/` and `workspace/` trees belong to the PUID/PGID in `.env`.
   If necessary use `sudo chown -R YOUR_UID:YOUR_GID state workspace` on **these copies only**.
   Secrets should be readable only by the owner. Do not share a host Python venv across architectures.
8. Start this bundle, run health and semantic tests, then connect Open WebUI. Keep the old
   installation and backups until sessions, memories and credentials are confirmed intact.
   Roll back by stopping this bundle and returning to the untouched old state/version.

## Troubleshooting and ARM64 limits

- `no matching manifest`: inspect the current image tag (`docker buildx imagetools inspect ...`).
  Both latest images had ARM64 manifests when checked, but future publication failures are possible.
- Source main and published latest are moving targets. If a CLI flag, SDK API or Node layout
  changes, the build/probe should fail visibly; pin a known working digest and review release notes.
- Python sample uses Serena's Python LSP. Other languages can require additional runtimes,
  downloads or architecture-specific binaries; an ARM64 Serena image does not guarantee every
  language server supports Linux ARM64. Extend the derivative explicitly for extra dependencies.
- First activation can be slow and requires download access. Inspect Serena logs for LSP startup
  errors. Large monorepos may exceed Pi RAM; exclude generated directories and index fewer folders.
- A model that cannot emit valid tool calls may answer without using Serena. A successful HTTP
  health check does not establish model/tool compatibility. Use the explicit chat prompts.
- If `lab` already has aliases `hermes` or `serena`, resolve those conflicts before deployment;
  Docker DNS can otherwise return the wrong service.
- Permission errors: compare `id`, PUID/PGID and bind-mounted ownership. Avoid `chmod 777`.
- Hermes local terminal starts in `/workspace` through both environment and config. It can change
  its directory within a session. Changes inside the image layer disappear on container replacement;
  keep durable files in the documented bind mounts.
