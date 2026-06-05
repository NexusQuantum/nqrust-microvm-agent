#!/usr/bin/env bash
# nqrust-microvm preflight — run on the TARGET host (over ssh) before installing.
# Emits human-readable checks plus a machine-readable summary block the agent parses.
# Exit 0 = safe to proceed (may include warnings); non-zero = hard blocker.
set -uo pipefail

ok=0; warn=0; fail=0
say()  { printf '%s\n' "$*"; }
pass() { say "  [ OK ]  $*"; ok=$((ok+1)); }
warng(){ say "  [WARN]  $*"; warn=$((warn+1)); }
bad()  { say "  [FAIL]  $*"; fail=$((fail+1)); }

say "== nqrust-microvm preflight =="

# --- architecture (installer ships x86_64 musl only) ---
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then pass "arch $ARCH"; else bad "arch $ARCH (requires x86_64)"; fi

# --- OS (installer targets Debian/Ubuntu apt) ---
OS_ID=""; OS_VER=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"; OS_VER="${VERSION_ID:-}"
  if printf '%s %s' "${ID:-}" "${ID_LIKE:-}" | grep -qiE 'debian|ubuntu'; then
    pass "os ${OS_ID} ${OS_VER}"
  else
    bad "os ${OS_ID} ${OS_VER} (requires Debian/Ubuntu)"
  fi
else
  bad "cannot read /etc/os-release"
fi

# --- KVM ---
KVM="no"
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then pass "/dev/kvm present and accessible"; KVM="ok";
  else warng "/dev/kvm present but not r/w for $(id -un) (install runs as root, usually fine)"; KVM="present"; fi
else
  bad "/dev/kvm missing — KVM/virtualization not available"
fi
VIRT="no"
if grep -qE '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then pass "cpu virtualization flags present"; VIRT="ok"; else bad "no vmx/svm in /proc/cpuinfo (nested virt off?)"; fi

# --- memory / disk ---
RAM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
if [ "${RAM_GB:-0}" -ge 4 ]; then pass "RAM ${RAM_GB}GB"; else warng "RAM ${RAM_GB}GB (<4GB recommended)"; fi
DISK_GB="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)"
if [ "${DISK_GB:-0}" -ge 20 ]; then pass "disk free ${DISK_GB}GB on /"; else warng "disk free ${DISK_GB}GB on / (<20GB recommended)"; fi

# --- tmux (required to drive the installer TUI) ---
TMUX_STATE="missing"
if command -v tmux >/dev/null 2>&1; then pass "tmux $(tmux -V 2>/dev/null | awk '{print $2}')"; TMUX_STATE="ok";
else
  warng "tmux missing — attempting install"
  if command -v apt-get >/dev/null 2>&1 && (sudo -n true 2>/dev/null || [ "$(id -u)" = 0 ]); then
    if (sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux) >/dev/null 2>&1 && command -v tmux >/dev/null 2>&1; then
      pass "tmux installed"; TMUX_STATE="ok"
    else bad "tmux install failed (need it to drive the TUI)"; fi
  else bad "tmux missing and cannot auto-install (no passwordless sudo)"; fi
fi

# --- prior install (idempotency) ---
PRIOR="none"
if systemctl list-unit-files 2>/dev/null | grep -qE 'nqrust-(manager|agent)\.service' \
   || [ -d /opt/nqrust-microvm ] || [ -d /etc/nqrust-microvm ]; then
  warng "existing nqrust-microvm install detected (offer skip/repair/upgrade/reinstall)"; PRIOR="present"
else pass "no prior nqrust-microvm install"; fi

# --- GitHub reachability (release-vs-local artifact decision) ---
REL_URL="https://github.com/NexusQuantum/NQRust-MicroVM/releases/latest/download/nqr-installer-x86_64-linux-musl"
GH="no"
if curl -fsSL -I -m 8 "$REL_URL" >/dev/null 2>&1; then pass "GitHub release reachable"; GH="yes"; else warng "GitHub release NOT reachable — will use local artifact fallback"; fi

RESULT="pass"; [ "$fail" -gt 0 ] && RESULT="fail"
say ""
say "=== PREFLIGHT SUMMARY ==="
say "ARCH=$ARCH"
say "OS=$OS_ID"
say "OS_VERSION=$OS_VER"
say "KVM=$KVM"
say "VIRT=$VIRT"
say "RAM_GB=${RAM_GB:-0}"
say "DISK_FREE_GB=${DISK_GB:-0}"
say "TMUX=$TMUX_STATE"
say "PRIOR_INSTALL=$PRIOR"
say "GITHUB_REACHABLE=$GH"
say "CHECKS_OK=$ok CHECKS_WARN=$warn CHECKS_FAIL=$fail"
say "RESULT=$RESULT"

[ "$RESULT" = "pass" ] || exit 2
exit 0
