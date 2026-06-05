#!/usr/bin/env bash
# nqrust-microvm POST-INSTALL REPORT — run on the TARGET host (over ssh) after the
# install verifies. Collects ground-truth state (services, versions, ports, paths,
# disk, access URLs) with NO secrets and NO auth required, so the agent can compose a
# human-readable install report. Emits human lines, then a machine `=== REPORT ===` block.
# Grounded in https://microvm.nexusquantum.id (manager :18080, agent :9090,
# guest-agent :9000, UI :3000, PostgreSQL :5432).
set -uo pipefail
say() { printf '%s\n' "$*"; }
BIN=/opt/nqrust-microvm/bin
# is-active returns non-zero for inactive/absent, so capture stdout and ignore the exit code
# (a bare `|| echo` would print BOTH the state and the fallback).
active() { local s; s="$(systemctl is-active "$1" 2>/dev/null)"; printf '%s' "${s:-unknown}"; }
since() { systemctl show -p ActiveEnterTimestamp --value "$1" 2>/dev/null; }

say "== nqrust-microvm post-install report =="

# --- services ---
S_MANAGER="$(active nqrust-manager)"; S_AGENT="$(active nqrust-agent)"
S_GUEST="$(active nqrust-guest-agent)"; S_PG="$(active postgresql)"
S_UI="$(active nqrust-ui)"

# --- firecracker version (safe to probe). The PLATFORM version comes from the API /health;
#     do NOT run nqrust-manager/agent with --version — those binaries START THE SERVICE. ---
FC="$(command -v firecracker 2>/dev/null || { [ -x "$BIN/firecracker" ] && echo "$BIN/firecracker"; } || echo "")"
V_FC="$([ -n "$FC" ] && "$FC" --version 2>/dev/null | head -1 | tr -d '\r' || echo "")"

# --- manager health (no auth) ---
HEALTH="unreachable"; API_VER=""
H="$(curl -fsS -m6 http://127.0.0.1:18080/health 2>/dev/null)"
if [ -n "$H" ]; then
  HEALTH="$(printf '%s' "$H" | grep -oE '"status":"[^"]*"' | cut -d'"' -f4)"
  API_VER="$(printf '%s' "$H" | grep -oE '"version":"[^"]*"' | cut -d'"' -f4)"
  [ -z "$HEALTH" ] && HEALTH="ok"
fi

# --- listening ports (which of the platform ports are bound, + bind addr) ---
PORTS=""
for p in 18080 9090 9000 3000 5432; do
  line="$(ss -tlnH 2>/dev/null | awk -v P=":$p" '$4 ~ P"$"{print $4; exit}')"
  [ -n "$line" ] && PORTS="$PORTS $p=$line"
done

# --- config files (paths from the unit files — readable without root, unlike the 0700 dir;
#     basenames only, NEVER contents — they hold secrets) ---
CFGS="$(grep -rhoE 'EnvironmentFile=-?[^ ]+' /etc/systemd/system/nqrust-*.service 2>/dev/null \
  | sed 's/EnvironmentFile=-\{0,1\}//' | xargs -r -n1 basename 2>/dev/null | sort -u | paste -sd, -)"

# --- data paths + disk ---
DISK_FREE_GB="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc 0-9)"
DISK_TOTAL_GB="$(df -BG --output=size / 2>/dev/null | tail -1 | tr -dc 0-9)"
du_of() { [ -d "$1" ] && { timeout 15 du -sh "$1" 2>/dev/null | cut -f1 || echo "?"; } || echo "-"; }
SZ_VMS="$(du_of /srv/fc/vms)"; SZ_IMAGES="$(du_of /srv/images)"; SZ_OPT="$(du_of /opt/nqrust-microvm)"

# --- host IP for access URLs: prefer the address the operator actually connected to
#     (SSH_CONNECTION field 3 = server IP); fall back to the default-route uplink. ---
IP="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $3}')"
if [ -z "$IP" ]; then
  UPLINK="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
  IP="$(ip -o -4 addr show "${UPLINK:-lo}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
fi
[ -z "$IP" ] && IP="<host>"

# --- infer install mode from what's running ---
MODE="Unknown"
if   [ "$S_MANAGER" = "active" ] && [ "$S_AGENT" = "active" ] && [ "$S_UI" = "active" ]; then MODE="Production"
elif [ "$S_MANAGER" = "active" ] && [ "$S_AGENT" = "active" ]; then MODE="Minimal"
elif [ "$S_MANAGER" = "active" ]; then MODE="Manager-only"
elif [ "$S_AGENT" = "active" ]; then MODE="Agent-only"
fi
KVM="missing"; [ -e /dev/kvm ] && KVM="present"

# --- overall health verdict ---
STATUS="degraded"
{ [ "$S_MANAGER" = "active" ] && [ "$S_AGENT" = "active" ] && [ "$HEALTH" = "ok" ]; } && STATUS="healthy"

say ""
say "=== REPORT ==="
say "STATUS=$STATUS"
say "INSTALL_MODE=$MODE"
say "HOSTNAME=$(hostname 2>/dev/null)"
say "HOST_IP=$IP"
say "SVC_MANAGER=$S_MANAGER"
say "SVC_AGENT=$S_AGENT"
say "SVC_GUEST_AGENT=$S_GUEST"
say "SVC_UI=$S_UI"
say "SVC_POSTGRES=$S_PG"
say "PLATFORM_VERSION=$API_VER"
say "VER_FIRECRACKER=$V_FC"
say "API_HEALTH=$HEALTH"
say "API_VERSION=$API_VER"
say "PORTS_BOUND=${PORTS# }"
say "CONFIG_FILES=$CFGS"
say "KVM=$KVM"
say "DISK_FREE_GB=${DISK_FREE_GB:-0}"
say "DISK_TOTAL_GB=${DISK_TOTAL_GB:-0}"
say "SIZE_VMS=$SZ_VMS"
say "SIZE_IMAGES=$SZ_IMAGES"
say "SIZE_OPT=$SZ_OPT"
say "MANAGER_STARTED=$(since nqrust-manager)"
say "URL_MANAGER=http://$IP:18080"
say "URL_UI=$([ "$S_UI" = active ] && echo "http://$IP:3000" || echo "n/a (not Production)")"
say "URL_AGENT=http://$IP:9090"
say "DEFAULT_LOGIN=root/root (CHANGE THIS)"
say "=== END REPORT ==="
[ "$STATUS" = "healthy" ]
