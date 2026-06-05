#!/usr/bin/env bash
# Build the `nqvm` CLI and stage it at this skill's bin/nqvm, so the agent can push it to a
# target host (nqvm is NOT a published release asset yet). Run on the OPERATOR machine.
#
# Source discovery order:  $NQRUST_MICROVM_SRC  →  common local paths  →  (with --clone) git clone
# Output:  <skill>/bin/nqvm   (a static x86_64 musl binary when possible; portable to any target)
#
# Usage: scripts/build-nqvm.sh [--clone]
set -euo pipefail
say() { printf '%s\n' "$*"; }
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$SKILL_DIR/bin/nqvm"
TARGET="x86_64-unknown-linux-musl"
REPO_URL="https://github.com/NexusQuantum/NQRust-MicroVM"

find_src() {
  [ -n "${NQRUST_MICROVM_SRC:-}" ] && [ -d "$NQRUST_MICROVM_SRC/crates/nqvm-cli" ] && { echo "$NQRUST_MICROVM_SRC"; return; }
  for d in \
    "$HOME/nexus/nqrust-microvm/NQRust-MicroVM" \
    "$HOME/NQRust-MicroVM" \
    "$PWD/NQRust-MicroVM" \
    "$SKILL_DIR/.nqrust-src/NQRust-MicroVM"; do
    [ -d "$d/crates/nqvm-cli" ] && { echo "$d"; return; }
  done
  return 1
}

SRC="$(find_src || true)"
if [ -z "$SRC" ]; then
  if [ "${1:-}" = "--clone" ]; then
    SRC="$SKILL_DIR/.nqrust-src/NQRust-MicroVM"
    say "→ cloning $REPO_URL (shallow) into $SRC"
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 "$REPO_URL" "$SRC"
  else
    say "✗ NQRust-MicroVM source not found."
    say "  Set NQRUST_MICROVM_SRC=/path/to/NQRust-MicroVM, or re-run with --clone."
    exit 2
  fi
fi
say "✓ source: $SRC"

command -v cargo >/dev/null 2>&1 || { say "✗ cargo not found — install Rust (https://rustup.rs)."; exit 3; }

# Prefer a static musl build (portable to any target host); fall back to the host's default target.
BUILT=""
if rustup target list --installed 2>/dev/null | grep -q "$TARGET" || rustup target add "$TARGET" 2>/dev/null; then
  say "→ building nqvm ($TARGET, static)…"
  if ( cd "$SRC" && cargo build --release --target "$TARGET" -p nqvm-cli ); then
    BUILT="$SRC/target/$TARGET/release/nqvm"
  fi
fi
if [ -z "$BUILT" ] || [ ! -x "$BUILT" ]; then
  say "→ musl unavailable; building for the host's default target (may not be portable to musl-only hosts)…"
  ( cd "$SRC" && cargo build --release -p nqvm-cli )
  BUILT="$SRC/target/release/nqvm"
fi
[ -x "$BUILT" ] || { say "✗ build produced no nqvm binary"; exit 4; }

mkdir -p "$SKILL_DIR/bin"
install -m755 "$BUILT" "$OUT"
say "✓ staged → $OUT"
"$OUT" --help >/dev/null 2>&1 && say "✓ binary runs (nqvm --help ok)" || say "! built but --help failed — check the binary"
