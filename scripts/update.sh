#!/usr/bin/env bash
# Usage: bash scripts/update.sh [all|hermes|serena]
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-all}" in
  all) selected=(hermes serena) ;;
  hermes|serena) selected=("$1") ;;
  *) echo 'Usage: update.sh [all|hermes|serena]' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
[[ -f .env ]] || { echo 'Initialize first.' >&2; exit 1; }
mkdir -p backups versions
# Avoid overlapping updates. Lock is released even on failure.
exec 9>backups/.update.lock
flock -n 9 || { echo 'Another update is running.' >&2; exit 1; }
umask 077
docker network inspect lab >/dev/null
docker compose config --quiet
stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
backup="backups/$stamp"
mkdir "$backup"
# Preserve both current images BEFORE pull/build replaces a moving tag.
for service in hermes serena; do
  cid="$(docker compose ps -aq "$service")"
  [[ -n "$cid" ]] || { echo "No existing $service container. Use scripts/up.sh for first start." >&2; exit 1; }
  image_id="$(docker inspect --format '{{.Image}}' "$cid")"
  docker image tag "$image_id" "hermes-serena-rollback/$service:$stamp"
done
python3 - "$backup" "$stamp" <<'PY'
import json,sys
from pathlib import Path
p,stamp=sys.argv[1:]
Path(p,'rollback.json').write_text(json.dumps({'services':{
 s:{'image':f'hermes-serena-rollback/{s}:{stamp}','pull_policy':'never'}
 for s in ('hermes','serena')}},indent=2)+'\n')
PY
# Prepare new images while the current containers keep running. No state changes.
for service in "${selected[@]}"; do
  if [[ "$service" == hermes ]]; then docker compose pull hermes
  else docker compose build --pull serena; fi
done
# Quiesce BOTH sides so MCP sessions and SQLite state have a consistent boundary.
docker compose stop hermes serena
trap 'echo "Update interrupted/failed. Snapshot: $backup. Follow README rollback instructions; do not delete old images." >&2' ERR
# Exclude this directory (and avoid backing up open databases). Includes project .serena data.
tar -czf "$backup/data.tar.gz" .env state workspace
cp docker-compose.yml "$backup/compose-at-update.yml"
[[ ! -f docker-compose.lan.yml ]] || cp docker-compose.lan.yml "$backup/"
# Only recreate selected services. Restart both afterwards to reconnect Hermes MCP.
for service in "${selected[@]}"; do
  docker compose up -d --no-deps --no-build --pull never --force-recreate "$service"
done
docker compose up -d --no-build --pull never --no-recreate --wait --wait-timeout 300
bash scripts/health.sh
# Inspect records image IDs and digests; it deliberately does not dump env secrets.
for service in hermes serena; do
  cid="$(docker compose ps -q "$service")"
  image_id="$(docker inspect --format '{{.Image}}' "$cid")"
  docker image inspect --format '{{.Id}} {{json .RepoDigests}} {{json .Config.Labels}}' "$image_id" >"versions/$stamp-$service.txt"
done
trap - ERR
printf 'Update complete. Backup: %s\n' "$backup"
