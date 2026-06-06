# nqrust-microvm-agent

An AI agent that **installs and operates [NQRust-MicroVM](https://github.com/NexusQuantum/NQRust-MicroVM)
on a remote Linux host from natural language.**

- **Install** — it SSHes in, **detects the host's specs + network and recommends a configuration**
  (grounded in the official docs at [microvm.nexusquantum.id](https://microvm.nexusquantum.id)),
  drives the real `nqr-installer` TUI over tmux, verifies, and **writes a post-install report**.
- **Operate** — afterward, ask it to **create a microVM, start/stop/delete it, deploy a container
  or function, manage images/networks/snapshots** — it drives NQRust-MicroVM's own `nqvm` CLI
  over SSH against the manager API.

Powered by [RantaiClaw](https://github.com/RantAI-dev/RantAIClaw). This repo ships **only the
skills** (playbooks + helper scripts); the SSH/tmux capability lives in RantaiClaw itself as the
general-purpose `ssh` and `pty` tools (the `remote-install` feature).

> **New here? Start with the hands-on [TUTORIAL.md](TUTORIAL.md)** — step-by-step from a
> blank machine to a verified install, including a throwaway test target and the gotchas
> we hit validating it end-to-end (the 20 GB disk requirement, NAT-not-Bridged, provider
> quirks, and how to drive a long install to completion).

```
nqrust-install "on 10.0.0.5, ssh user ubuntu, key ~/.ssh/id_ed25519, production, NAT, with web UI"
```

---

## Prerequisites

1. **RantaiClaw with the remote-install tools** — the prebuilt bundle (below) ships it; from
   source, see *Getting a RantaiClaw with the tools*.
2. **An LLM provider** configured in RantaiClaw (`rantaiclaw onboard`) — the agent is model-driven.
3. **A target host:** Ubuntu/Debian **x86_64 with KVM** (`/dev/kvm`), reachable over SSH, with sudo.
   You do **not** need `ssh`/`tmux` on your own machine — RantaiClaw connects in-process and
   installs `tmux` on the target during preflight.

## Install

**Fastest — prebuilt bundle (recommended).** Ships a static `rantaiclaw` (with the ssh+pty
tools) + both skills + the `nqvm` CLI. You only add your LLM key. Linux x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/NexusQuantum/nqrust-microvm-agent/master/get.sh | bash
rantaiclaw onboard      # set your LLM provider + key
rantaiclaw chat
```

It downloads the latest [release](https://github.com/NexusQuantum/nqrust-microvm-agent/releases),
verifies the checksum, installs `rantaiclaw` to `~/.local/bin`, and deploys the skills. (Same
thing via the release: `curl -fsSL https://github.com/NexusQuantum/nqrust-microvm-agent/releases/latest/download/install.sh | bash`.)

**From source** (other platforms, or you already run your own RantaiClaw):

```bash
git clone https://github.com/NexusQuantum/nqrust-microvm-agent
cd nqrust-microvm-agent
./install.sh            # deploys the skills, verifies the tools, stages nqvm
```

`install.sh` refuses to proceed if your `rantaiclaw` lacks the `ssh`/`pty` tools, so you can't
end up with a skill that silently can't run.

## Tutorial — install your first host

**1. Set up the agent** (once, on your laptop):
```bash
curl -fsSL https://raw.githubusercontent.com/NexusQuantum/nqrust-microvm-agent/master/get.sh | bash
rantaiclaw onboard      # pick your LLM provider + paste an API key
```

**2. Have a target ready** — a Linux box the agent will SSH into: Ubuntu/Debian **x86_64 with KVM**
(`/dev/kvm`; nested virt if it's itself a VM), **≥ 30 GB free disk**, ≥ 4 GB RAM, reachable over
SSH with **sudo**. (No KVM → can't run Firecracker; use bare metal or a nested-virt VM.)

**3. Tell the agent how to reach it** — it needs **host + user + one SSH credential**, plus sudo:

| What you give | Example phrasing |
|---|---|
| Password (used for SSH + sudo) | `ssh user ubuntu password 's3cret'` |
| SSH key + passwordless sudo | `ssh user ubuntu, key ~/.ssh/id_ed25519` |
| SSH key + a separate sudo password | `ssh user ubuntu, key ~/.ssh/id_ed25519, sudo password 's3cret'` |
| ssh-agent (nothing secret typed) | `ssh user ubuntu, use my ssh agent` |

Credentials pass only through the tool call — never written to disk or echoed back. Logging in as
`root`, or a user with **passwordless sudo**, is smoothest.

**4. Run it:**
```bash
rantaiclaw chat
```
Then paste (give it all the settings up front):
```
Install nqrust-microvm on 10.0.0.5, ssh user ubuntu, key ~/.ssh/id_ed25519.
Minimal mode, NAT networking. Discover the host first, then drive the installer to
completion ONE KEY AT A TIME, verify, and report. Work autonomously; I'll reply "continue".
```
It connects → profiles the host and recommends a config → drives the real installer → verifies →
reports. `ssh`/`pty` are **always-ask**, so approve each step with **Y**; when it pauses, reply
**`continue`**. Watch live with `tmux attach -t nqr` on the target.

Done → **Manager API** `http://10.0.0.5:18080`, **Web UI** `http://10.0.0.5:3000` (Production).
Default login **root/root — change it.**

**5. Operate it** — same chat, plain language:
```
on 10.0.0.5 create a microVM named web, 2 vCPU 1GB from the ubuntu-24.04 image, start it
list my VMs   ·   stop web   ·   snapshot web   ·   delete web
```

## Getting a RantaiClaw with the tools

The `ssh` + `pty` tools are general RantaiClaw capabilities behind the `remote-install` feature.

- **Once upstreamed** (PR in progress to RantAI-dev/RantAIClaw): any official build with
  `--features remote-install` (it's in `default`) has them — `rantaiclaw update` just works.
- **Until then**, build from the feature branch:
  ```bash
  git clone https://github.com/RantAI-dev/RantAIClaw
  cd RantAIClaw && git checkout feature/ssh-pty-tools
  cargo build --release --features remote-install
  install -m755 target/release/rantaiclaw ~/.local/bin/rantaiclaw
  ```

## Usage

```bash
# one-shot
nqrust-install "on 192.0.2.10, ssh user ubuntu, key ~/.ssh/id_ed25519; production, NAT, local postgres, with web UI"

# interactive — give it as little as you like; it asks for the rest
nqrust-install
> install nqrust-microvm on 10.0.0.42, ssh user root password 's3cret'
```

The agent will: connect → preflight → ask the config it doesn't know (mode, networking,
database, UI/Docker) and show a summary → drive the installer TUI → verify → report URLs.
`ssh`/`pty` are set to **always-ask**, so you approve (press **Y**) before privileged remote
actions. Watch it live on the target with `tmux attach -t nqr`.

When it finishes: **Manager** `http://<host>:18080`, **Web UI** `http://<host>:3000`
(default login `root`/`root` — change it).

## Try it safely first

```bash
multipass launch 24.04 --name nqr-target --cpus 4 --memory 8G --disk 40G
multipass exec nqr-target -- bash -lc 'test -e /dev/kvm && echo kvm-ok'   # must print kvm-ok
multipass info nqr-target | grep IPv4
nqrust-install "on <that-ip>, ssh user ubuntu password ..."
```

## Operate it (after install)

Once a host is installed, ask the agent to run it — it drives NQRust-MicroVM's own **`nqvm`**
CLI over SSH (against the manager API):

```bash
rantaiclaw agent -m "on 10.0.0.5 (ssh ubuntu, key ~/.ssh/id_ed25519): create a microVM \
  named web, 2 vCPU, 1GB, from the ubuntu-24.04 image, and start it"
# also: "list my VMs", "stop web", "snapshot web", "deploy nginx as a container", "delete web"
```

The **`nqrust-microvm-operate`** skill resolves names→IDs, creates/starts/stops/deletes VMs,
deploys containers & functions, and manages images/networks/snapshots. The CLI isn't a published
release asset yet, so the agent fetches it by building locally and pushing it to the host (the
skill handles this); default login is `root`/`root` — change it.

## What's in here

```
skill/nqrust-microvm/SKILL.md          # install playbook (screen-map of the installer TUI)
skill/nqrust-microvm/scripts/          # discover / resolve-artifact / verify / smoke-test / report
skill/nqrust-microvm/RUNBOOK.md        # detailed runbook + troubleshooting
skill/nqrust-microvm-operate/SKILL.md  # day-2 ops playbook (nqvm CLI command reference + recipes)
skill/nqrust-microvm-operate/scripts/  # ensure-nqvm (get the CLI onto the host)
install.sh                             # deploy both skills into your RantaiClaw
bin/nqrust-install                     # thin convenience wrapper
```

## Troubleshooting

See `skill/nqrust-microvm/RUNBOOK.md` — auth, "no tmux session", host-key changes, long
Build/Base-Image phases, rollback (`nqr-installer uninstall --non-interactive --force`).
