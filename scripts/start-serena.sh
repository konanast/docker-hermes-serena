#!/usr/bin/env bash
set -euo pipefail
umask 0022
cd /workspace
exec /workspaces/serena/.venv/bin/serena start-mcp-server \
  --transport streamable-http --host 0.0.0.0 --port 9121 \
  --context desktop-app --agent-interface tools \
  --enable-web-dashboard false --open-web-dashboard false \
  --enable-gui-log-window false
