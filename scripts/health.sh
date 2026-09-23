#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose ps
docker compose exec -T serena /workspaces/serena/.venv/bin/python /bundle/check-serena.py
docker compose exec -T hermes python - <<'CHECK'
import json, os, urllib.request
for path in ('/health', '/v1/models', '/v1/toolsets'):
    req = urllib.request.Request('http://127.0.0.1:8642'+path,
        headers={'Authorization': 'Bearer '+os.environ['API_SERVER_KEY']})
    data = json.load(urllib.request.urlopen(req, timeout=20))
    print(path, json.dumps(data))
req = urllib.request.Request(os.environ['MODEL_BASE_URL'].rstrip('/')+'/models',
    headers={'Authorization': 'Bearer '+os.environ['MODEL_API_KEY']})
with urllib.request.urlopen(req, timeout=20) as r:
    print('LAN model /models:', r.status)
CHECK
