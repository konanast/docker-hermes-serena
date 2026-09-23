# Verification record — 2026-09-23

## Official source inspected

Hermes checkout: `07646a7f72773e08197ac138295fba8f317973d2`, project version `0.21.4`.
Serena checkout: `dc97aba74a5fa339d5b3b1a824ccf311b7db04a3`, project version `2.0.0.dev0`.
These identify inspected source, not a claim that a moving image tag contains that exact commit.

| Topic | Official evidence |
|---|---|
| Hermes image, ARM64 CI, main/latest publication | [docker workflow](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/.github/workflows/docker.yml) |
| Hermes image startup, state home and user remapping | [Dockerfile](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/Dockerfile), [Compose](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/docker-compose.yml) |
| Gateway command, authentication, API port and health | [API guide](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/website/docs/user-guide/features/api-server.md) |
| Open WebUI integration and server-side tool execution | [Open WebUI guide](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/website/docs/user-guide/messaging/open-webui.md) |
| MCP configuration, local terminal and model schema | [config example](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/cli-config.yaml.example) |
| API agents use api_server toolsets | [API implementation](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/gateway/platforms/api_server.py), [MCP toolset merge](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/hermes_cli/tools_config.py) |
| Custom model endpoint/key resolution | [provider implementation](https://github.com/NousResearch/hermes-agent/blob/07646a7f72773e08197ac138295fba8f317973d2/hermes_cli/runtime_provider_backends.py) |
| Serena image and ARM64 publication | [workflow](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/.github/workflows/docker.yml), [Dockerfile](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/Dockerfile) |
| Serena streamable-http, dashboard flags, context and CLI | [CLI](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/src/serena/cli.py) |
| Serena global/project config keys | [global template](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/src/serena/resources/serena_config.template.yml), [project template](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/src/serena/resources/project.template.yml) |
| Initial instructions/session ID | [agent](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/src/serena/agent.py), [project activation](https://github.com/oraios/serena/blob/dc97aba74a5fa339d5b3b1a824ccf311b7db04a3/src/serena/tools/config_tools.py) |

Important choices: use the official Hermes entrypoint and `gateway run`, not a made-up
standalone serve command. Use Serena `serena start-mcp-server --transport streamable-http`
for `/mcp`, not its older example's SSE transport. Use `desktop-app` context so
`initial_instructions` is available: current `oaicompat-agent` excludes it even though
current project activation requires the session ID it supplies. No upstream code is patched.
The bundled MCP clients tolerate both older three-item and current two-item transport tuples,
and current snake_case MCP response fields.

## Live registry manifests

Registry API queries returned HTTP 200 and the following OCI index/platform digests.
These are the observed tags, **not a promise of runtime validation** and not hard-coded defaults.

| Image | Index digest | Linux ARM64 manifest |
|---|---|---|
| `nousresearch/hermes-agent:latest` | `sha256:e8467cd815c7577f8246c52b1f5627d6f2c7cdb6487faacd72c12ba091770147` | `sha256:6389ba8a9dbe122f09b002090b83a75f734d13f6613232a92c4a380a0ceda9fd` |
| `ghcr.io/oraios/serena:latest` | `sha256:d52d564750a7b8b3880900eaba826622a5f4aa7d374236fc9463a6b23246bda1` | `sha256:a9205d7803acdfdebd1cae213378fb9c7ac97a64ea19be588c0f9fbbc7a354cc` |

Both indexes also contained amd64 and attestation entries. To pin the observed indexes,
replace `:latest` with `@sha256:...` in the corresponding `.env` image variable.
Docker's `platform: linux/arm64` selects the ARM64 member.

## Executed tests

- YAML parsing for Compose, override and configurations; Bash syntax checks; Python AST checks.
- Initialization in a temporary bundle: secret generation, private `.env` permissions,
  repeat initialization preserving byte-identical existing configs and secret.
- Update script with **mocked Docker commands**, using real temporary files and tar backups:
  all/hermes/serena selection, unchanged data, backup creation and an injected Serena build
  failure that stopped before service shutdown. This tests script control flow, not Docker behavior.
- Installed current Serena source with Python 3.11.16 and its declared dependencies on
  **x86-64**, including MCP 2.2.0. Launched its actual streamable HTTP server with dashboards off.
- Live MCP initialization and tool discovery passed. `initial_instructions` and session-ID-based
  project activation passed for the sample. This was a local host process, not the Docker image.
- Python symbol operations were attempted but **did not pass**: the LSP's uvx dependency path
  tried downloading Python 3.13.15 and that download failed in this environment. No successful
  symbol-index or find-symbol runtime claim is made. The README includes the repeatable on-Pi test.

## Not tested here

No Docker executable/daemon or Raspberry Pi was available. Consequently image pulling/building
with Docker, Compose schema validation by the actual CLI, container boot, bind-mount permissions,
Docker DNS, s6 privilege dropping, update/rollback against real containers, ARM64 language-server
execution, Hermes agent turns, the user's LAN model and end-to-end Open WebUI chats remain untested.
The Serena derivative is source-reviewed, not image-built here. Source plus manifests establish
that official ARM64 images exist; they do not establish Pi performance or every language's support.

First-use LSP downloads require egress and available upstream artifacts. Language-specific native
binaries may not support ARM64. Indexing can be slow or memory-heavy on a Pi. Future `latest`
images can change flags, SDK types or layouts; use digests once you have validated your deployment.
