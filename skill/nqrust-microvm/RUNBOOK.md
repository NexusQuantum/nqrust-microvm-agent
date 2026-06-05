# NQRust-MicroVM Installer Agent — Runbook

How to build, deploy, and run the RantaiClaw installer agent.

## 1. Build the patched RantaiClaw binary

The `ssh` and `pty` tools live behind the `remote-install` cargo feature (in `default`).

```bash
cd packages/rantaiclaw            # or the feature/ssh-pty-tools worktree
cargo build --release --features remote-install
# -> target/release/rantaiclaw   (install to ~/.local/bin/rantaiclaw)
```

The operator host needs `tmux` and `ssh` is NOT required locally (russh is in-process);
`tmux` is only required on the **target** (preflight installs it).

## 2. Deploy the skill

```bash
scripts/deploy-nqrust-skill.sh             # default profile
rantaiclaw skills list | grep nqrust-microvm
```

## 3. Run it (CLI / REPL)

```bash
rantaiclaw agent -m "install nqrust-microvm on 192.0.2.10 over ssh, user ubuntu, \
  key ~/.ssh/id_ed25519; production mode, NAT networking, local postgres, with web UI"
```
or interactively:
```bash
rantaiclaw repl
> install nqrust-microvm on the host at 10.0.0.42, ssh user root password '<pw>'
```
The agent connects, runs preflight, asks for any missing config, drives the installer TUI
over tmux, verifies, and reports the manager (`:18080`) and UI (`:3000`) URLs.

## 4. Local mechanics test (no remote host)

Proves the tmux drive end-to-end against the real installer TUI, locally:
```bash
# in rantaiclaw repl / agent, the model issues:
#  pty start  {session:"t", target:"local", command:"/path/to/nqr-installer install"}
#  pty wait   {session:"t", until:"NQR-MicroVM Installer"}
#  pty screen {session:"t"}           # should show the Welcome screen
#  pty send   {session:"t", keys:["Enter"]}
#  pty wait   {session:"t", until:"Select Installation Mode"}
#  pty stop   {session:"t"}
```
(Do not let it proceed past Preflight locally unless you actually want to install.)

## 5. Full remote integration test

Requirements: a fresh **Ubuntu/Debian x86_64** host with **KVM** (`/dev/kvm`), reachable over
SSH, with sudo. A nested-virt cloud VM or a local multipass VM works:
```bash
multipass launch 24.04 --name nqr-target --cpus 4 --memory 8G --disk 40G
multipass exec nqr-target -- sudo bash -c 'test -e /dev/kvm && echo kvm-ok'   # must print kvm-ok
```
Then prompt the agent to install onto `nqr-target`'s IP. Expected sequence:
1. `ssh connect` succeeds (TOFU records the host key in `~/.rantaiclaw/ssh_known_hosts.json`).
2. `preflight.sh` → `RESULT=pass`, `TMUX=ok`, `GITHUB_REACHABLE=yes`.
3. `resolve-artifact.sh` downloads `nqr-installer` (or scp local fallback).
4. The agent drives Welcome → Mode → Network → Config → Preflight → Progress → Verify → Complete.
5. `verify.sh` → `MANAGER=active AGENT=active HEALTH=ok RESULT=pass`.
6. Web UI reachable at `http://<target>:3000` (default login root/root — change it).

## 6. Rollback

```bash
# agent runs, on failure or on request:
sudo /tmp/nqr-installer uninstall --non-interactive --force   # add --keep-data / --keep-database
```

## 7. Troubleshooting

- **Skill not listed:** it may be gated — confirm `rantaiclaw skills list` shows it as enabled,
  and that the deploy copied it into the *active* profile's `workspace/skills/`.
- **`pty` says "no tmux session":** call `pty start` first; tmux must be installed on the target
  (preflight installs it; otherwise `sudo apt-get install -y tmux`).
- **Auth fails:** for key auth pass `auth.key_path` (or `auth.key_pem`) + `passphrase`; ssh-agent
  is not yet supported — use key or password.
- **Host-key changed (connect rejected):** a prior key is recorded; if the host was legitimately
  rebuilt, remove its entry from `~/.rantaiclaw/ssh_known_hosts.json`.
- **Long install phases:** Build/Download and Base Images can take several minutes; the agent
  uses `pty wait {stable:true, timeout_ms:600000}` — tmux keeps the session alive across SSH drops.
