# NQRust-MicroVM agent — Quickstart (pre-set-up bundle)

This bundle contains everything to install **and operate** NQRust-MicroVM on remote hosts from
a prompt: a prebuilt **rantaiclaw** agent (with the `ssh` + `pty` tools), both skills, and the
`nqvm` CLI. You only add your **LLM provider key**.

## 1. Set it up (once, on your laptop)

```bash
tar xzf nqrust-microvm-agent-*-x86_64-linux.tar.gz
cd nqrust-microvm-agent-*-x86_64-linux
./setup.sh
```
`setup.sh` installs `rantaiclaw` to `~/.local/bin`, runs `rantaiclaw onboard` (set your provider +
API key — OpenRouter / Anthropic / MiniMax), and deploys the two skills.

> Linux x86_64 only (the binary is static, runs on any modern distro). Other platforms: build
> from source — see the repo README.

## 2. Install a host

The **target** must be: Ubuntu/Debian **x86_64 with KVM** (`/dev/kvm`; nested virt if it's a VM),
**≥ 30 GB free disk**, ≥ 4 GB RAM, reachable over **SSH with sudo**. You do *not* need ssh/tmux on
your laptop — the agent connects in-process and installs tmux on the target.

```bash
rantaiclaw chat
```
Paste a request with **all** settings (or it will stop to ask):
```
Install nqrust-microvm on 10.0.0.5 over SSH (user ubuntu, password 's3cret').
Minimal mode, NAT networking, local PostgreSQL, default paths, no Docker.
Discover the host, drive the installer TUI in tmux to completion ONE KEY AT A TIME,
then verify and report. Work autonomously; if you pause I'll reply "continue".
```
When it pauses, reply **`continue`**. It connects → profiles the host and recommends a config →
drives the real installer → verifies → gives you a post-install report. Approve each privileged
step with **Y**.

Result: **Manager API** `http://<host>:18080`, **Web UI** `http://<host>:3000` (Production mode).
Default login **root / root — change it.**

## 3. Operate it (day-2)

Same chat, plain language:
```
on 10.0.0.5 (ssh ubuntu): create a microVM named web, 2 vCPU, 1GB, from the ubuntu-24.04 image, start it
list my VMs   ·   stop web   ·   snapshot web   ·   deploy nginx as a container   ·   delete web
```

## Gotchas (the three that matter)

- **Use `rantaiclaw chat`, not `agent -m`.** `chat` is one persistent process that keeps the SSH +
  tmux session alive across turns; reply **`continue`** when it pauses. `agent -m` is one-shot.
- **NAT, not Bridged.** Bridged re-bridges the host's single NIC and can drop your SSH mid-install
  (the agent recommends NAT by default).
- **Provider strictness / credits.** A TUI drive is many model calls. OpenRouter / Anthropic are
  lenient; **MiniMax** can throw `tool id … not found (2013)` → type **`/retry`**. Keep credits topped up.

Full walkthrough + troubleshooting: `skill/nqrust-microvm/RUNBOOK.md` and the repo `TUTORIAL.md`.
