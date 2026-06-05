#!/usr/bin/env bash
# Install the nqrust-microvm installer skill into your local RantaiClaw.
# Usage: ./install.sh [profile]    (default profile: "default")
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '%s\n' "$*"; }

# 1. RantaiClaw present?
if ! command -v rantaiclaw >/dev/null 2>&1; then
  say "✗ rantaiclaw not found on PATH."
  say "  Install a RantaiClaw build that includes the remote-install tools (ssh + pty)."
  say "  See README.md → 'Getting a RantaiClaw with the tools'."
  exit 1
fi
say "✓ rantaiclaw $(rantaiclaw --version | awk '{print $2}')"

# 2. Are the ssh + pty tools compiled into this binary? (the skill is useless without them)
BIN="$(command -v rantaiclaw)"
# grep -c (not -q) so `strings` drains fully — grep -q closes the pipe early and the
# resulting SIGPIPE would trip `set -o pipefail` even on a match.
HAS_TOOLS="$(strings "$BIN" 2>/dev/null | grep -cF "Secure SSH transport to a remote host" || true)"
if [ "${HAS_TOOLS:-0}" -eq 0 ]; then
  say "✗ This rantaiclaw was built WITHOUT the remote-install tools (ssh + pty)."
  say "  Rebuild with:  cargo build --release --features remote-install"
  say "  (or install a release that bundles them — see README.md)."
  exit 1
fi
say "✓ ssh + pty tools present in this binary"

# 3. Deploy the skill into the active profile's workspace
ROOT="${RANTAICLAW_HOME:-$HOME/.rantaiclaw}"
PROFILE="${1:-${RANTAICLAW_PROFILE:-default}}"
DEST="$ROOT/profiles/$PROFILE/workspace/skills/nqrust-microvm"
mkdir -p "$DEST"
cp -r "$HERE/skill/nqrust-microvm/." "$DEST/"
chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true
say "✓ skill deployed → $DEST"

# 4. Confirm it loads + nudge on LLM key
LOADED="$(rantaiclaw skills list 2>/dev/null | grep -ci nqrust-microvm || true)"
if [ "${LOADED:-0}" -gt 0 ]; then
  say "✓ skill loaded (rantaiclaw skills list)"
else
  say "! skill copied but not listed — is profile '$PROFILE' the active one?"
fi

# 5. Optional: link the wrapper onto PATH if ~/.local/bin exists
if [ -d "$HOME/.local/bin" ]; then
  ln -sf "$HERE/bin/nqrust-install" "$HOME/.local/bin/nqrust-install"
  say "✓ wrapper linked → ~/.local/bin/nqrust-install"
fi

say ""
say "Done. Make sure an LLM provider is configured (rantaiclaw onboard), then:"
say "  nqrust-install \"on 10.0.0.5, ssh user ubuntu, key ~/.ssh/id_ed25519, production, NAT\""
say "  # or:  rantaiclaw agent -m \"install nqrust-microvm on 10.0.0.5 ...\""
