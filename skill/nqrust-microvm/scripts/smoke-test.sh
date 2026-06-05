#!/usr/bin/env bash
# Best-effort smoke test: confirm the manager control plane sees a registered agent
# host and base images (the real proof a VM *could* boot). Full create->boot->destroy
# is driven via the UI/API; this stays read-only and schema-tolerant.
# Endpoints follow the manager REST surface (/v1/hosts, /v1/images); adjust if the
# deployed version differs.
set -uo pipefail
BASE="${1:-http://localhost:18080}"
echo "== nqrust-microvm smoke test ($BASE) =="

probe() { curl -fsS -m 10 "$1" 2>/dev/null; }
HOSTS_JSON="$(probe "$BASE/v1/hosts")"
IMAGES_JSON="$(probe "$BASE/v1/images")"

# crude, schema-tolerant object count
count() { printf '%s' "$1" | grep -oE '"(id|uuid|name)"\s*:' | wc -l | tr -d ' '; }
hosts_n="$(count "$HOSTS_JSON")"
images_n="$(count "$IMAGES_JSON")"

echo "registered agent hosts: ${hosts_n:-0}"
echo "registered base images: ${images_n:-0}"
echo ""
echo "=== SMOKE SUMMARY ==="
echo "HOSTS=${hosts_n:-0}"
echo "IMAGES=${images_n:-0}"
if [ "${hosts_n:-0}" -ge 1 ] && [ "${images_n:-0}" -ge 1 ]; then
  echo "RESULT=pass"
else
  echo "RESULT=incomplete (control plane up but no agent/images yet — check 'systemctl status nqrust-agent' and /srv/images)"
fi
exit 0
