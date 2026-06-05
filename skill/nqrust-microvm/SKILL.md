---
name: nqrust-microvm
description: Install & configure NQRust-MicroVM on a remote Linux host by driving the nqr-installer TUI over tmux via SSH. On first run it detects the host's specs + network and recommends a configuration, grounded in the official docs (microvm.nexusquantum.id); on finish it produces a post-install report.
version: 0.3.0
tags: [installer, microvm, firecracker, tmux, ssh, infra]
---

# NQRust-MicroVM remote installer

You install **NQRust-MicroVM** (Firecracker microVM platform: `manager` :18080, `agent`
:9090, web UI :3000, PostgreSQL) onto a remote Ubuntu/Debian x86_64 host. You do NOT
re-implement install logic — you **drive the product's own `nqr-installer` TUI over tmux**
and add: secure SSH, conversational config, artifact provisioning, verification, rollback.

You use two built-in tools: **`ssh`** (transport) and **`pty`** (tmux screen-driver). The
helper scripts referenced below live in this skill's `scripts/` directory — read them with
`file_read` and upload them with `ssh` `push`. (If the operator says the helper scripts are
already on the target, just run them with `ssh exec` instead of pushing.)

## Autonomous operation (critical)

Run the WHOLE installation to completion in ONE session. You already have every setting — do NOT
pause, ask for confirmation, or end your turn until the install is verified complete or has
definitively failed. If you get stuck on a screen, re-read it (`pty wait {stable:true}` → `pty
screen`) and retry the key — never stop mid-drive. Narrate briefly, but ALWAYS immediately follow
with the next tool call.

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

**Golden rule for the TUI: never send keys to a moving screen, and send ONE key at a time.**
For every keystroke loop: `pty send` ONE key → `pty wait {session, stable:true, timeout_ms:4000}`
→ `pty screen` → CONFIRM the highlighted item/field actually changed before the next key. The TUI
redraws with a delay over SSH; if you read immediately you see the previous frame and wrongly think
the key didn't register. If the highlight did NOT move, `pty wait {stable:true}` again and re-read —
do NOT spam more keys (you'll overshoot). In field lists (Configuration screen) move down one row at
a time and re-read the focused field name each time.

## Procedure

### 1. Parse the request & connect
From the user's prompt extract host/IP, username, and credential (password OR key path/content).
If anything is missing, ASK. Then `ssh connect`. Never echo or log the password/passphrase.

### 2. Discover the host (specs + network) — do this on FIRST contact
- `ssh push` `scripts/discover.sh` → `/tmp/nqr-discover.sh`; `ssh exec "bash /tmp/nqr-discover.sh"`.
- Parse the `=== DISCOVERY ===` KEY=VALUE block.
  - **`BLOCKERS` non-empty** → STOP and report it (e.g. `arch=…`, `no-kvm`, `no-virt-flags`, `disk<20G`, `unsupported-os`). Per the [system requirements](https://microvm.nexusquantum.id) the host can't run NQRust-MicroVM.
  - **`PRIOR_INSTALL=present`** → ask the operator: skip / repair / upgrade / uninstall+reinstall. Don't blindly re-run.
  - **`TMUX=missing`** → `ssh exec "sudo apt-get update && sudo apt-get install -y tmux"` (you need it for the drive).
  - Remember `GITHUB_REACHABLE` for step 4.

### 3. Recommend a configuration, then confirm
Don't ask cold — turn the discovery into a **recommendation**, then let the operator adjust.
Show the operator TWO short tables:

**(a) Discovery** — what you found: `OS` · `CPU_CORES`/`CPU_MODEL` · `VIRT`/`KVM` · `RAM_GB` · `DISK_FREE_GB`/`DISK_TOTAL_GB` · `PRIMARY_NIC` + `PRIMARY_IP` + `GATEWAY` · `NIC_COUNT` · `VIRTUALIZED` · `PORTS_BUSY` · `GITHUB_REACHABLE`.

**(b) Recommended configuration** — derive each setting from the discovery using the
**Recommendation rules** below (which encode the official docs). For every setting give the
**recommendation + a one-line "why"**. Then print the final settings and get an explicit
**"proceed, or change X?"** before driving the installer.

If the operator's original prompt already pinned some settings, honor those and only
recommend the rest.

## Recommendation rules (from the official docs — https://microvm.nexusquantum.id)

Map the `DISCOVERY` values to each installer setting. Always surface the recommendation + the
reason, and let the operator override. (Docs: min = x86_64+KVM, 4 GB RAM, 20 GB disk,
Ubuntu 22.04/24.04 or Debian 11; recommended = 8 GB+ RAM, 50 GB+ disk, Ubuntu 24.04.)

- **Install mode** — multi-host? joining an existing manager → **Agent Only**; this host is the
  control plane for workers → **Manager Only**. Single host (default): **Production**
  (Manager+Agent+UI) when it meets the *recommended* bar (`RAM_GB ≥ 8` and `DISK_FREE_GB ≥ 50`);
  if it only meets the *minimum* (`RAM_GB ≥ 4`, `DISK_FREE_GB 20–50`), recommend **Minimal**
  (no UI) to stay light. Never recommend Development (that's build-from-source).
- **Network mode** — the installer offers **NAT / Bridged / Isolated** (VXLAN overlay is set up
  later in the UI for multi-host):
  - **NAT — default recommendation.** Private subnet, VMs get DHCP + internet via host NAT, and
    it does NOT touch the host uplink → **safe, won't drop your SSH**. Best when
    `VIRTUALIZED≠none`, `PRIMARY_IP_PRIVATE=yes`, or `NIC_COUNT=1`.
  - **Bridged** — only if the operator wants VMs to have **real LAN IPs**. Needs a physical
    uplink (`PRIMARY_NIC`). ⚠️ It re-bridges that NIC; if you're connected through it
    (`NIC_COUNT=1`) the install can **drop your SSH** and may need a reboot. Recommend only when
    `NIC_COUNT ≥ 2` or there's out-of-band access; otherwise warn and keep NAT.
  - **Isolated** — air-gapped / no-egress hosts; VMs reach only each other.
- **Disk** (`DISK_FREE_GB`) — `<20` → **blocked** (installer pre-flight fails). `20–35` → OK but
  tight (base images are ~8 GB) → lean toward Minimal + Container-Runtime=No. `≥50` → ideal.
- **Container runtime / Docker** (Docker-in-VM + ~2.2 GB container-runtime image + bun/python
  function runtimes) — recommend **Yes** when `DISK_FREE_GB ≥ ~40` and the operator wants
  containers/functions; **No** for a lean install or tight disk (saves ~5 GB of downloads).
- **Database** — **local PostgreSQL** (documented default; the installer provisions it).
- **Paths** — keep defaults: `/opt/nqrust-microvm` (bin+ui), `/srv/fc/vms`, `/srv/images`,
  `/etc/nqrust-microvm` (manager.env/agent.env/ui.env), `/var/log/nqrust-microvm`.
- **After install** — report the documented access URLs: Manager API `:18080`, Web UI `:3000`
  (Production), Agent `:9090`; default login `root`/`root` → tell the operator to change it.

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

### 7. Post-install report (always, on success)
Produce a written report the operator can keep. Gather ground truth, then compose it.
- `ssh push` `scripts/report.sh` → `ssh exec "bash /tmp/nqr-report.sh"`; parse the
  `=== REPORT ===` block (services, versions, `API_HEALTH`/`API_VERSION`, `PORTS_BOUND`,
  `INSTALL_MODE`, disk/sizes, access URLs). The script needs **no auth** and prints **no secrets**.
- Write a markdown report and present it (and save it for the operator). Include:
  - **What was installed** — `INSTALL_MODE`, component versions, NQRust-MicroVM release.
  - **The configuration you chose** — mode, network mode, Docker/container-runtime, paths, DB
    (from steps 3–5; this is the rationale the operator agreed to).
  - **Host** — the step-2 discovery summary (OS/CPU/RAM/disk/KVM/NICs).
  - **Result & health** — `STATUS`, service states, `API_HEALTH`, ports bound, disk used by
    `/srv/images` + `/srv/fc/vms`.
  - **Access** — `URL_MANAGER`, `URL_UI` (if Production), `URL_AGENT`, and the **`root`/`root`
    default login with a prompt to change it**.
  - **Next steps** — point at the **`nqrust-microvm-operate`** skill to create VMs etc. via the
    `nqvm` CLI ("ask me to create a VM").
- If `STATUS=degraded` (a service down or API unhealthy), say so plainly and surface which check
  failed rather than declaring success.

### 8. Rollback (only on failure)
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
