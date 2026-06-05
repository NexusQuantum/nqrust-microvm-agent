#!/usr/bin/env bash
# Ensure the `nqvm` CLI is available on this host so the agent can drive day-2 ops.
# Run on the TARGET host (over ssh). Resolution order:
#   (1) an existing working binary (DEST or on PATH) → reuse it
#   (2) the published release asset (forward-compatible; may 404 until it's published)
#   (3) exit 10 → signal the agent to PUSH a locally-built binary to DEST
# Usage: ensure-nqvm.sh [DEST]      (DEST default /tmp/nqvm)
# Prints NQVM=<path> + SOURCE=<present|release|none> on the last lines.
set -uo pipefail
DEST="${1:-/tmp/nqvm}"
REL="https://github.com/NexusQuantum/NQRust-MicroVM/releases/latest/download/nqvm-x86_64-linux-musl"
works() { "$1" --help >/dev/null 2>&1; }   # nqvm has NO --version; --help exits 0

# (1) reuse an existing working binary (explicit DEST first, then PATH)
for c in "$DEST" "$(command -v nqvm 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && works "$c" && { echo "NQVM=$c"; echo "SOURCE=present"; exit 0; }
done

# (2) try the published release asset
if curl -fsSL -m30 -o "$DEST" "$REL" 2>/dev/null && chmod +x "$DEST" && works "$DEST"; then
  echo "NQVM=$DEST"; echo "SOURCE=release"; exit 0
fi
rm -f "$DEST" 2>/dev/null

# (3) not available remotely — the agent must push a local build
echo "NQVM="; echo "SOURCE=none"
echo "HINT=no nqvm on host and release asset unavailable; push a locally-built nqvm to $DEST" >&2
exit 10
