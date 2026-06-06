#!/usr/bin/env bash
# One-command setup for the pre-set-up NQRust-MicroVM agent bundle.
# Installs the bundled rantaiclaw (with ssh+pty), deploys both skills, and onboards your LLM key.
# Usage: ./setup.sh            (override install dir with BINDIR=, profile with RANTAICLAW_PROFILE=)
set -euo pipefail
say() { printf '%s\n' "$*"; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. does the bundled binary run on this host?
if ! "$HERE/bin/rantaiclaw" --version >/dev/null 2>&1; then
  say "✗ The bundled rantaiclaw won't run here (architecture/libc mismatch)."
  say "  This bundle is $(cat "$HERE/VERSION" 2>/dev/null | grep ^arch= | cut -d= -f2). Build from source for other platforms."
  exit 1
fi
say "✓ rantaiclaw $("$HERE/bin/rantaiclaw" --version | awk '{print $2}') runs on this host"

# 2. confirm the ssh + pty tools are compiled in.
# grep -c (not -q): -q closes the pipe early → SIGPIPE trips `set -o pipefail` even on a match.
HAS_TOOLS="$(strings "$HERE/bin/rantaiclaw" 2>/dev/null | grep -cF "Secure SSH transport to a remote host" || true)"
if [ "${HAS_TOOLS:-0}" -ge 1 ]; then
  say "✓ ssh + pty tools present"
else
  say "✗ binary is missing the remote-install tools — bad bundle."; exit 1
fi

# 3. install onto PATH
DEST="${BINDIR:-$HOME/.local/bin}"
mkdir -p "$DEST"
install -m755 "$HERE/bin/rantaiclaw" "$DEST/rantaiclaw"
say "✓ installed → $DEST/rantaiclaw"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) say "  ⚠ $DEST is not on your PATH — add it:  export PATH=\"$DEST:\$PATH\"" ;;
esac

# 4. LLM provider + key (reuse rantaiclaw's own onboarding if nothing is configured yet)
PROFILE="${RANTAICLAW_PROFILE:-default}"
CFG="$HOME/.rantaiclaw/profiles/$PROFILE/config.toml"
if [ ! -f "$CFG" ]; then
  say ""
  say "→ No config yet. Launching 'rantaiclaw onboard' to set your LLM provider + API key…"
  say "  (or Ctrl-C and set api_key/default_provider in $CFG yourself)"
  "$DEST/rantaiclaw" onboard || say "! onboard skipped — configure a provider/key before running"
else
  say "✓ existing config: $CFG (leaving it as-is)"
fi

# 5. deploy the skills AFTER onboarding (onboard --force can wipe the workspace)
SK="$HOME/.rantaiclaw/profiles/$PROFILE/workspace/skills"
for s in nqrust-microvm nqrust-microvm-operate; do
  mkdir -p "$SK/$s"
  cp -r "$HERE/skill/$s/." "$SK/$s/"
  chmod +x "$SK/$s"/scripts/*.sh 2>/dev/null || true
done
say "✓ skills deployed → $SK"
LOADED="$("$DEST/rantaiclaw" skills list 2>/dev/null | grep -ci nqrust || true)"
[ "${LOADED:-0}" -ge 2 ] && say "✓ both skills load" || say "! re-check 'rantaiclaw skills list' (profile=$PROFILE)"

cat <<EOF

Done. Start the agent:
  rantaiclaw chat

Then paste an install request (give ALL settings up front), e.g.:
  Install nqrust-microvm on 10.0.0.5 over SSH (user ubuntu, password 's3cret').
  Minimal mode, NAT networking, local PostgreSQL, default paths, no Docker.
  Discover the host, drive the installer TUI in tmux to completion ONE KEY AT A TIME,
  then verify and report. Work autonomously; if you pause I'll reply "continue".

After it's installed, just ask:  "on 10.0.0.5 create a microVM named web, 2 vCPU 1GB, start it"
See QUICKSTART.md for requirements + gotchas.
EOF
