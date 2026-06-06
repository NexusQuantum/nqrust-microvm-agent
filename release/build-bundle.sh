#!/usr/bin/env bash
# Assemble a "pre-set-up agent" release bundle: a prebuilt rantaiclaw (with the ssh+pty tools)
# + both skills (incl. the nqvm CLI) + a one-command setup. Produces dist/<bundle>.tar.gz.
#
# Usage: release/build-bundle.sh <path-to-rantaiclaw-binary> [tag]
#   e.g. release/build-bundle.sh ~/rc/target/x86_64-unknown-linux-musl/release/rantaiclaw v0.1.0
set -euo pipefail
say() { printf '%s\n' "$*"; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

RC_BIN="${1:?usage: build-bundle.sh <rantaiclaw-binary> [tag]}"
TAG="${2:-v0.1.0}"
ARCH="$(uname -m)"
NAME="nqrust-microvm-agent-${TAG}-${ARCH}-linux"
OUT="$REPO/dist"
STAGE="$OUT/$NAME"

[ -x "$RC_BIN" ] || { say "✗ rantaiclaw binary not found/executable: $RC_BIN"; exit 1; }

# the binary MUST carry the ssh/pty tools or the skills can't run.
# grep -c (not -q): -q closes the pipe on first match → SIGPIPE trips `set -o pipefail` even on a hit.
HAS_TOOLS="$(strings "$RC_BIN" 2>/dev/null | grep -cF "Secure SSH transport to a remote host" || true)"
[ "${HAS_TOOLS:-0}" -ge 1 ] \
  || { say "✗ that rantaiclaw was built WITHOUT remote-install (ssh+pty) — rebuild with the feature"; exit 1; }

# the operate skill needs the bundled nqvm CLI — build it if it's not staged yet
if [ ! -x "$REPO/skill/nqrust-microvm-operate/bin/nqvm" ]; then
  say "→ nqvm not staged; building it…"
  bash "$REPO/skill/nqrust-microvm-operate/scripts/build-nqvm.sh"
fi

say "→ staging $NAME"
rm -rf "$STAGE"; mkdir -p "$STAGE/bin"
install -m755 "$RC_BIN" "$STAGE/bin/rantaiclaw"

# skills (copy, then drop any local scratch the build helper may have created)
for s in nqrust-microvm nqrust-microvm-operate; do
  mkdir -p "$STAGE/skill/$s"
  cp -r "$REPO/skill/$s/." "$STAGE/skill/$s/"
  chmod +x "$STAGE/skill/$s"/scripts/*.sh 2>/dev/null || true
done
rm -rf "$STAGE/skill/nqrust-microvm-operate/.nqrust-src"

# setup + docs
install -m755 "$HERE/files/setup.sh" "$STAGE/setup.sh"
cp "$HERE/files/QUICKSTART.md" "$STAGE/QUICKSTART.md"
[ -f "$REPO/TUTORIAL.md" ] && cp "$REPO/TUTORIAL.md" "$STAGE/TUTORIAL.md"
[ -f "$REPO/README.md" ]   && cp "$REPO/README.md"   "$STAGE/README.md"
[ -f "$REPO/LICENSE" ] && cp "$REPO/LICENSE" "$STAGE/LICENSE" 2>/dev/null || true
RC_VER="$("$RC_BIN" --version 2>/dev/null | awk '{print $2}')"
cat > "$STAGE/VERSION" <<EOF
bundle=$TAG
rantaiclaw=$RC_VER
skills=nqrust-microvm,$(grep -m1 '^version:' "$REPO/skill/nqrust-microvm/SKILL.md" | awk '{print $2}');nqrust-microvm-operate,$(grep -m1 '^version:' "$REPO/skill/nqrust-microvm-operate/SKILL.md" | awk '{print $2}')
arch=$ARCH-linux
EOF

# tarball + checksum
say "→ packing tarball"
( cd "$OUT" && tar czf "$NAME.tar.gz" "$NAME" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
say "✓ $OUT/$NAME.tar.gz"
say "  $(cat "$OUT/$NAME.tar.gz.sha256")"
say "  size: $(du -h "$OUT/$NAME.tar.gz" | cut -f1)"
