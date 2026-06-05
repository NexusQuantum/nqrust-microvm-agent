#!/usr/bin/env bash
# Verify an nqrust-microvm install on the TARGET host. Run after the installer completes.
# Exit 0 = healthy; non-zero = problems. Emits a machine-readable summary block.
set -uo pipefail
fail=0
echo "== nqrust-microvm verify =="

for svc in nqrust-manager nqrust-agent; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then echo "  [ OK ]  $svc active";
  else echo "  [FAIL]  $svc not active"; fail=1; fi
done

HEALTH="no"
for url in http://localhost:18080/v1/health http://localhost:18080/health http://127.0.0.1:18080/v1/health; do
  if curl -fsS -m 8 "$url" >/dev/null 2>&1; then echo "  [ OK ]  manager health ($url)"; HEALTH="ok"; break; fi
done
[ "$HEALTH" = ok ] || { echo "  [FAIL]  manager API not responding on :18080"; fail=1; }

if curl -fsS -m 5 http://localhost:3000 >/dev/null 2>&1; then echo "  [ OK ]  web UI :3000";
else echo "  [WARN]  web UI :3000 not responding (may be disabled or still starting)"; fi

echo ""
echo "=== VERIFY SUMMARY ==="
echo "MANAGER=$(systemctl is-active nqrust-manager 2>/dev/null || echo inactive)"
echo "AGENT=$(systemctl is-active nqrust-agent 2>/dev/null || echo inactive)"
echo "HEALTH=$HEALTH"
echo "RESULT=$([ "$fail" = 0 ] && echo pass || echo fail)"
[ "$fail" = 0 ] || exit 2
exit 0
