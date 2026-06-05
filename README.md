# nqrust-microvm-agent

An AI agent that **installs [NQRust-MicroVM](https://github.com/NexusQuantum/NQRust-MicroVM)
on a remote Linux host from a single prompt** — it SSHes in, runs preflight, gathers the config
conversationally, drives the real `nqr-installer` TUI over tmux, verifies, and reports.

Powered by [RantaiClaw](https://github.com/RantAI-dev/RantAIClaw). This repo ships **only the
skill** (a playbook + helper scripts); the SSH/tmux capability lives in RantaiClaw itself as the
general-purpose `ssh` and `pty` tools (the `remote-install` feature).

```
nqrust-install "on 10.0.0.5, ssh user ubuntu, key ~/.ssh/id_ed25519, production, NAT, with web UI"
```

---

## Prerequisites

1. **RantaiClaw with the remote-install tools.** See *Getting a RantaiClaw with the tools* below.
2. **An LLM provider** configured in RantaiClaw (`rantaiclaw onboard`) — the agent is model-driven.
3. **A target host:** Ubuntu/Debian **x86_64 with KVM** (`/dev/kvm`), reachable over SSH, with sudo.
   You do **not** need `ssh`/`tmux` on your own machine — RantaiClaw connects in-process and
   installs `tmux` on the target during preflight.

## Install

```bash
git clone <this-repo> nqrust-microvm-agent
cd nqrust-microvm-agent
./install.sh            # deploys the skill, verifies the tools, links the wrapper
```

`install.sh` refuses to proceed if your `rantaiclaw` lacks the `ssh`/`pty` tools, so you can't
end up with a skill that silently can't run.

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

## What's in here

```
skill/nqrust-microvm/SKILL.md      # the agent playbook (screen-map of the installer TUI)
skill/nqrust-microvm/scripts/      # preflight / resolve-artifact / verify / smoke-test
skill/nqrust-microvm/RUNBOOK.md    # detailed runbook + troubleshooting
install.sh                         # deploy into your RantaiClaw
bin/nqrust-install                 # thin convenience wrapper
```

## Troubleshooting

See `skill/nqrust-microvm/RUNBOOK.md` — auth, "no tmux session", host-key changes, long
Build/Base-Image phases, rollback (`nqr-installer uninstall --non-interactive --force`).
