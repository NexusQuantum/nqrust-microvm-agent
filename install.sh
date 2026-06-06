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
# grep -a reads the binary directly — no dependency on `strings` (binutils, not always installed).
HAS_TOOLS="$(grep -acF "Secure SSH transport to a remote host" "$BIN" || true)"
if [ "${HAS_TOOLS:-0}" -eq 0 ]; then
  say "✗ This rantaiclaw was built WITHOUT the remote-install tools (ssh + pty)."
  say "  Rebuild with:  cargo build --release --features remote-install"
  say "  (or install a release that bundles them — see README.md)."
  exit 1
fi
say "✓ ssh + pty tools present in this binary"

# 2b. Stage the nqvm CLI for the operate skill (it is NOT a published release asset yet, so the
#     agent pushes this bundled binary to target hosts). Best-effort — needs the NQRust-MicroVM
#     source + cargo; if it can't build, the operate skill builds/pushes on demand instead.
if [ ! -x "$HERE/skill/nqrust-microvm-operate/bin/nqvm" ]; then
  say "→ staging nqvm for the operate skill (best-effort)…"
  if bash "$HERE/skill/nqrust-microvm-operate/scripts/build-nqvm.sh" >/dev/null 2>&1; then
    say "✓ nqvm staged → skill/nqrust-microvm-operate/bin/nqvm"
  else
    say "! nqvm not staged (no source/cargo) — set NQRUST_MICROVM_SRC or run"
    say "  skill/nqrust-microvm-operate/scripts/build-nqvm.sh --clone later. The operate skill"
    say "  also builds/pushes on demand; see its SKILL.md."
  fi
else
  say "✓ nqvm already staged"
fi

# 3. Deploy the skills into the active profile's workspace
#    - nqrust-microvm          → install (drive the installer TUI)
#    - nqrust-microvm-operate  → day-2 ops (create VMs etc. via the nqvm CLI)
ROOT="${RANTAICLAW_HOME:-$HOME/.rantaiclaw}"
PROFILE="${1:-${RANTAICLAW_PROFILE:-default}}"
SKILLS_DIR="$ROOT/profiles/$PROFILE/workspace/skills"
for s in nqrust-microvm nqrust-microvm-operate; do
  DEST="$SKILLS_DIR/$s"
  mkdir -p "$DEST"
  cp -r "$HERE/skill/$s/." "$DEST/"
  chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true
  say "✓ skill deployed → $DEST"
done

# 4. Confirm they load + nudge on LLM key
LOADED="$(rantaiclaw skills list 2>/dev/null | grep -ci nqrust-microvm || true)"
if [ "${LOADED:-0}" -ge 2 ]; then
  say "✓ both skills loaded (rantaiclaw skills list)"
elif [ "${LOADED:-0}" -gt 0 ]; then
  say "✓ skill(s) loaded ($LOADED) — re-check 'rantaiclaw skills list'"
else
  say "! skills copied but not listed — is profile '$PROFILE' the active one?"
fi

# 5. Optional: link the wrapper onto PATH if ~/.local/bin exists
if [ -d "$HOME/.local/bin" ]; then
  ln -sf "$HERE/bin/nqrust-install" "$HOME/.local/bin/nqrust-install"
  say "✓ wrapper linked → ~/.local/bin/nqrust-install"
fi

say ""
say "Done. Make sure an LLM provider is configured (rantaiclaw onboard), then:"
say "  # install:"
say "  nqrust-install \"on 10.0.0.5, ssh user ubuntu, key ~/.ssh/id_ed25519, production, NAT\""
say "  # operate (after install):"
say "  rantaiclaw agent -m \"on 10.0.0.5 (ssh ubuntu), create a microVM named web, 2 vCPU 1GB\""
