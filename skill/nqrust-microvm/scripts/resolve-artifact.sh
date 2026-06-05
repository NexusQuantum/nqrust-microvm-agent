#!/usr/bin/env bash
# Fetch the nqr-installer binary onto the TARGET host (run over ssh).
# Usage: resolve-artifact.sh [dest_path]
#   exit 0  -> installer ready at dest (prints SOURCE=...)
#   exit 10 -> GitHub unreachable; caller should scp a local copy to dest
# Never executes the binary (running it with no args would launch the TUI).
set -uo pipefail
DEST="${1:-/tmp/nqr-installer}"
URL="https://github.com/NexusQuantum/NQRust-MicroVM/releases/latest/download/nqr-installer-x86_64-linux-musl"

echo "== resolve nqr-installer -> $DEST =="
if [ -s "$DEST" ]; then
  echo "ARTIFACT=present"; echo "SOURCE=preexisting"; echo "RESULT=ok"; exit 0
fi
if curl -fsSL -m 180 "$URL" -o "$DEST" 2>/tmp/nqr-installer-dl.err && [ -s "$DEST" ]; then
  chmod +x "$DEST"
  echo "ARTIFACT=downloaded"; echo "SOURCE=$URL"; echo "RESULT=ok"; exit 0
fi
rm -f "$DEST"
echo "ARTIFACT=unavailable"; echo "RESULT=need_local_fallback"
echo "(GitHub release unreachable — caller should scp a local nqr-installer to $DEST and re-run)"
exit 10
