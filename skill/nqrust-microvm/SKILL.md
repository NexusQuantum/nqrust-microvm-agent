---
name: nqrust-microvm
description: Install & configure NQRust-MicroVM on a remote Linux host by driving the nqr-installer TUI over tmux via SSH, gathering config conversationally.
version: 0.1.0
tags: [installer, microvm, firecracker, tmux, ssh, infra]
---

# NQRust-MicroVM remote installer

You install **NQRust-MicroVM** (Firecracker microVM platform: `manager` :18080, `agent`
:9090, web UI :3000, PostgreSQL) onto a remote Ubuntu/Debian x86_64 host. You do NOT
re-implement install logic — you **drive the product's own `nqr-installer` TUI over tmux**
and add: secure SSH, conversational config, artifact provisioning, verification, rollback.

You use two built-in tools: **`ssh`** (transport) and **`pty`** (tmux screen-driver). The
helper scripts referenced below live in this skill's `scripts/` directory — read them with
`file_read` and upload them with `ssh` `push`.

## Tool contracts (use exactly these)

`ssh` tool — `{ "action": ... }`:
- `connect`: `{action:"connect", host, port=22, user, auth:{method:"password"|"key"|"agent", password?, key_path?, key_pem?, passphrase?}}` → returns a `session` id (`user@host:port`).
- `exec`: `{action:"exec", session, command, timeout_secs=120}` → `{rc, stdout, stderr}`.
- `push`/`pull`: `{action:"push"|"pull", session, local_path, remote_path}`.
- `disconnect`: `{action:"disconnect", session}`.

`pty` tool — `{ "action": ... }` (tmux):
- `start`: `{action:"start", session="nqr", target:"<ssh session id>"|"local", command, cols=200, rows=50}`.
- `screen`: `{action:"screen", session}` → current rendered screen text.
- `send`: `{action:"send", session, keys:[ "Up","Down","Left","Right","Enter","Tab","BTab","Escape","Space","BSpace","C-c", {"text":"literal value"} ]}`.
- `wait`: `{action:"wait", session, until:"<regex>"?, stable:true?, timeout_ms=15000}` → settled screen.
- `stop`: `{action:"stop", session}`.

**Golden rule for the TUI: never send keys to a moving screen.** Before every keystroke do
`pty wait {until: "<anchor text of the screen you expect>"}` (or `{stable:true}`), then
`pty screen` to confirm which screen you're on, then `pty send`.

## Procedure

### 1. Parse the request & connect
From the user's prompt extract host/IP, username, and credential (password OR key path/content).
If anything is missing, ASK. Then `ssh connect`. Never echo or log the password/passphrase.

### 2. Preflight (idempotency + readiness)
- `ssh push` `scripts/preflight.sh` → `/tmp/nqr-preflight.sh`; `ssh exec "bash /tmp/nqr-preflight.sh"`.
- Parse the `=== PREFLIGHT SUMMARY ===` block.
  - `RESULT=fail` → STOP and report which check failed (arch≠x86_64, no KVM, wrong OS, no tmux).
  - `PRIOR_INSTALL=present` → ask the operator: **skip / repair / upgrade / uninstall+reinstall**. Do not blindly re-run.
  - Remember `GITHUB_REACHABLE` for step 4.

### 3. Gather config conversationally
Ask only the high-impact choices; state the default and a one-line tradeoff. Map answers to the
TUI fields in step 5. Defaults in (parens):
- **Install mode** (Production) — Production = Manager+Agent+UI on this host.
- **Network mode** (NAT) — NAT = isolated VMs behind the host. Bridged = VMs on the LAN (needs an uplink interface, **may require a reboot**). Isolated = VMs talk only to each other.
- **Database** (local) — local = installer provisions PostgreSQL here; or give a remote host/port.
- **Web UI** (yes), **Container runtime** Docker-in-VM (yes, ~2.2GB download), **Install Docker on host** (yes).
- Paths default to `/opt/nqrust-microvm`, `/srv/fc`, `/etc/nqrust-microvm` — only ask if they want custom.

Print a summary table of the final settings and get an explicit **"proceed?"** before step 5.

### 4. Provision the installer artifact
- `ssh push` `scripts/resolve-artifact.sh` → run `ssh exec "bash /tmp/nqr-resolve.sh /tmp/nqr-installer"`.
  - exit 0 → installer is at `/tmp/nqr-installer` on the target.
  - exit 10 (GitHub unreachable) → **local fallback**: `ssh push {local_path:"/home/<you>/nexus/nqrust-microvm/NQRust-MicroVM/target/release/nqr-installer", remote_path:"/tmp/nqr-installer"}` then `ssh exec "chmod +x /tmp/nqr-installer"`. (If you have no local build, build it or tell the operator.)

### 5. Drive the installer TUI over tmux
Launch it inside tmux on the target and pilot it:
- `pty start {session:"nqr", target:"<ssh session>", command:"sudo /tmp/nqr-installer install", cols:200, rows:50}`.
- If a `[sudo] password` line appears on `screen`, `pty send {keys:[{text:"<sudo password>"}, "Enter"]}` (scrubbed; only if sudo isn't already cached / not root).
- Then walk the screens. Each row: wait for the anchor, confirm with `screen`, send keys.

**Screen → drive map** (anchor text → keys). Pure-select screens: `Up`/`Down` to the choice, then `Enter`. Field screens (Config): `Down` to the row, `e` to edit, `{text:"value"}`, `Enter` to apply, then `Enter` again (when not editing) to advance.

| Screen (anchor text) | What to do |
|---|---|
| `NQR-MicroVM Installer` (Welcome) | `Enter` |
| `Select Installation Mode` | `Up`/`Down` to your mode (Production/Development/Manager Only/Agent Only/Minimal), `Enter` |
| `Network Configuration` | `Up`/`Down` to NAT/Bridged/Isolated. If **Bridged**: `Tab` to the uplink panel, `Up`/`Down` to the interface. `Enter` |
| `Configuration` | For each field you're changing (Install/Data/Config Directory, Database Host/Port/Name/User, Install Docker, Container Runtime): `Down`/`Up` to the row, `e`, `{text:"value"}`, `Enter`. Booleans take `yes`/`no`. When done (not editing) `Enter` to continue |
| `Pre-flight Checks` | Read the result. If `All checks passed` (or warnings only) `Enter` to start install. If `Some checks failed`, `Esc` back / report |
| `Installation Progress` | Poll: `pty wait {until:"Enter.*verification|Installation Progress", stable:true, timeout_ms:600000}`; long phases (Build/Download, Base Images) take minutes. When all phases complete, `Enter` |
| `Installation Verification` | Read items; `Enter` |
| `Installation Complete` | Success. Note Access URLs. If Bridged and it offers reboot (`r to reboot`), CONFIRM with the operator before sending `r`; otherwise `Enter`/`q` to exit |
| `Installation Error` (`Installation failed`) | Capture the Error Details box. Go to step 7 (rollback) |

Narrate progress to the operator as you go (which screen, which phase).

### 6. Verify
- `ssh push` + `ssh exec "bash /tmp/nqr-verify.sh"` (`scripts/verify.sh`). Parse `VERIFY SUMMARY`.
- Optionally `scripts/smoke-test.sh` to confirm the agent + base images registered.
- Report: manager `http://<host>:18080`, UI `http://<host>:3000`, default login (warn to change it), and the verify result.

### 7. Rollback (only on failure)
Offer the product's own uninstall: `ssh exec "sudo /tmp/nqr-installer uninstall --non-interactive --force"` (add `--keep-data`/`--keep-database` if the operator wants). Pull `/var/log/nqrust-install/` and the tmux scrollback (`pty screen`) for diagnosis. Then `pty stop` and `ssh disconnect`.

## Safety
- Targets are usually private LAN IPs — that's expected; the `ssh` tool allows them.
- Secrets (ssh password/passphrase, sudo password, db password) are passed only through tool
  args; never print them, never write them to files on disk, never put them in `pty send` logs
  the operator can see beyond what's necessary.
- This is a privileged remote operation — honor approval prompts; preview the plan and the
  config summary before the first keystroke; confirm before any reboot.

## Multi-host
To install on several hosts, repeat the procedure per host (each `ssh connect` is a separate
session keyed by `user@host:port`; each tmux session can use a distinct name). Report a
per-host result table at the end.
