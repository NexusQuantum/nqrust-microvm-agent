#!/usr/bin/env bash
# Online installer for the NQRust-MicroVM agent. Downloads the latest release bundle
# (prebuilt static rantaiclaw with ssh+pty + both skills + the nqvm CLI), verifies its
# checksum, installs the binary, and deploys the skills. Non-interactive — safe to pipe:
#
#   curl -fsSL https://raw.githubusercontent.com/NexusQuantum/nqrust-microvm-agent/master/get.sh | bash
#
# It does NOT run onboard (that needs a terminal) — it prints the one command to run next.
# Env: NQR_AGENT_VERSION (default: latest) · BINDIR (default ~/.local/bin) · RANTAICLAW_PROFILE
set -euo pipefail
say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

REPO="NexusQuantum/nqrust-microvm-agent"
VER="${NQR_AGENT_VERSION:-latest}"
PROFILE="${RANTAICLAW_PROFILE:-default}"
DEST="${BINDIR:-$HOME/.local/bin}"

OS="$(uname -s)"; ARCH="$(uname -m)"
[ "$OS" = "Linux" ]    || die "this bundle is Linux x86_64 only (got $OS). Build from source: https://github.com/$REPO"
[ "$ARCH" = "x86_64" ] || die "this bundle is x86_64 only (got $ARCH). Build from source: https://github.com/$REPO"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"

# resolve the release tag (asset filename embeds the version)
if [ "$VER" = "latest" ]; then
  TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's#.*/tag/##')"
  [ -n "$TAG" ] || die "could not resolve the latest release tag"
else
  TAG="$VER"
fi
ASSET="nqrust-microvm-agent-${TAG}-x86_64-linux.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "→ downloading $ASSET …"
curl -fSL --progress-bar -o "$TMP/b.tar.gz" "$URL" || die "download failed: $URL"

# verify the checksum if the sidecar is published
if curl -fsSL -o "$TMP/b.sha256" "$URL.sha256" 2>/dev/null; then
  WANT="$(awk '{print $1}' "$TMP/b.sha256")"
  GOT="$(sha256sum "$TMP/b.tar.gz" | awk '{print $1}')"
  [ "$WANT" = "$GOT" ] || die "checksum mismatch (want $WANT, got $GOT) — aborting"
  say "✓ checksum verified"
fi

tar xzf "$TMP/b.tar.gz" -C "$TMP"
BDIR="$TMP/nqrust-microvm-agent-${TAG}-x86_64-linux"
RC="$BDIR/bin/rantaiclaw"
[ -x "$RC" ] || die "bundle is missing the rantaiclaw binary"
"$RC" --version >/dev/null 2>&1 || die "the bundled rantaiclaw won't run on this host (arch/libc mismatch)"

# tools present? grep -c (not -q): -q closes the pipe early → SIGPIPE trips pipefail even on a match
HAS="$(strings "$RC" 2>/dev/null | grep -cF "Secure SSH transport to a remote host" || true)"
[ "${HAS:-0}" -ge 1 ] || die "the bundled binary lacks the remote-install (ssh+pty) tools"

# install the binary
mkdir -p "$DEST"
install -m755 "$RC" "$DEST/rantaiclaw"
say "✓ installed rantaiclaw $("$RC" --version | awk '{print $2}') → $DEST/rantaiclaw"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) say "  ⚠ $DEST is not on your PATH — add it:  export PATH=\"$DEST:\$PATH\"" ;;
esac

# deploy both skills (incl. the bundled nqvm)
SK="$HOME/.rantaiclaw/profiles/$PROFILE/workspace/skills"
for s in nqrust-microvm nqrust-microvm-operate; do
  mkdir -p "$SK/$s"
  cp -r "$BDIR/skill/$s/." "$SK/$s/"
  chmod +x "$SK/$s"/scripts/*.sh 2>/dev/null || true
done
say "✓ skills deployed → $SK"

PATHHINT=""; case ":$PATH:" in *":$DEST:"*) ;; *) PATHHINT="export PATH=\"$DEST:\$PATH\"; ";; esac
cat <<EOF

Ready. Next:
  1) ${PATHHINT}configure your LLM provider/key:   rantaiclaw onboard   (or export OPENROUTER_API_KEY=…)
  2) start the agent:                              rantaiclaw chat
  3) ask it, e.g.:
       Install nqrust-microvm on 10.0.0.5 over SSH (user ubuntu, password '…').
       Minimal, NAT. Drive to completion; I'll reply "continue".
     After install:  on 10.0.0.5 create a microVM named web, 2 vCPU 1GB, start it
EOF
