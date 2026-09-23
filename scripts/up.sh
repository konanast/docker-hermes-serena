#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env && -f state/hermes/config.yaml ]] || { echo 'Run bash scripts/init.sh first.' >&2; exit 1; }
if grep -q '^MODEL_NAME=CHANGE_ME_MODEL' .env; then
  echo 'Set your LAN model settings in .env first.' >&2; exit 1
fi
docker network inspect lab >/dev/null
docker compose config --quiet
docker compose pull hermes
docker compose build --pull serena
docker compose up -d --no-build --wait --wait-timeout 300
