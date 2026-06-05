# Tutorial — Install NQRust-MicroVM on a host with the agent

A goal-oriented walkthrough. By the end you'll have driven a RantaiClaw agent to
install a working **NQRust-MicroVM** (manager + agent + PostgreSQL) on a Linux host,
from a prompt. This is the *real* procedure, including the gotchas we hit validating
it end-to-end against a live KVM VM.

## 0. Mental model

- You run **RantaiClaw** (the agent) on your machine.
- It SSHes to a **target host** and drives NQRust-MicroVM's own TUI installer
  (`nqr-installer`) over **tmux**.
- It uses two core RantaiClaw tools — **`ssh`** + **`pty`** — plus this repo's
  **`nqrust-microvm` skill** (the playbook). The agent does *not* reimplement the
  installer; it pilots the real one.

---

## 1. Prerequisites

### 1a. Target host (where NQRust-MicroVM is installed)
- **Ubuntu/Debian, x86_64**, with **KVM** (`/dev/kvm`; AMD-V/VT-x — and *nested* virt if the target is itself a VM).
- **≥ 20 GB free disk.** The installer's own pre-flight **fails below 20 GB**. Give it **30 GB+** — the base images alone are ~8 GB (container-runtime, bun/python runtimes, rootfs, kernel).
- ≥ 4 GB RAM, ~4 vCPU.
- **SSH reachable + sudo** (password or key).

> Need a throwaway target fast? See **Appendix A**.

### 1b. Your machine (where the agent runs)
- **RantaiClaw built with the `remote-install` tools.** Verify:
  ```bash
  rantaiclaw --version
  strings "$(command -v rantaiclaw)" | grep -q "Secure SSH transport to a remote host" \
    && echo "✓ ssh/pty tools present" || echo "✗ MISSING — build with --features remote-install"
  ```
  If missing, see the README → *Getting a RantaiClaw with the tools*.
- **An LLM provider configured** (the agent is model-driven — see §3).
- **Credits.** A full install drive is token-heavy (dozens of model calls carrying
  screen captures). Budget a few dollars; running dry mid-drive stalls it.

You do **not** need `ssh`/`tmux` on your own machine — RantaiClaw connects in-process
(russh) and installs `tmux` on the *target* during preflight.

---

## 2. Install the skill

```bash
git clone https://github.com/NexusQuantum/nqrust-microvm-agent
cd nqrust-microvm-agent && ./install.sh
```
`install.sh` refuses to proceed if your rantaiclaw lacks the ssh/pty tools, then deploys
the skill into your active profile and links a `nqrust-install` wrapper.

---

## 3. Configure the LLM provider

The agent needs a provider + key RantaiClaw can read (config **or** env). Example
(`~/.rantaiclaw/profiles/<profile>/config.toml`):
```toml
default_provider = "openrouter"
default_model    = "anthropic/claude-sonnet-4.6"
api_key          = "sk-or-..."   # top-level api_key = "API key for the selected provider"
```
…or export the provider env var (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`,
`MINIMAX_API_KEY`, …). Note: a process started by another tool may **not** inherit your
interactive shell's env — put the key in the config, or `source` your env file when
launching.

> ⚠️ **Provider tool-call-id strictness matters for long drives.** A TUI drive makes
> *many* tool calls. **OpenRouter / Anthropic** are lenient. **MiniMax** strictly
> validates tool-call ids and returns `400 ... tool id (...) not found (2013)` on
> tool-heavy screens — recoverable by typing **`/retry`**, but slower. Prefer a lenient
> provider for unattended runs.

---

## 4. Run it

### The honest truth about "autonomous"
`rantaiclaw agent -m "…"` is **one-shot** — the model tends to end its turn after a
handful of tool calls, so it won't finish a long install in a single command. And each
new `agent -m` process starts with empty `ssh`/`pty` registries, so you can't resume a
drive across processes. For a full drive you want **one persistent process** you keep
nudging:

**Recommended — interactive `chat` (persistent process keeps the ssh + tmux session alive across turns):**
```bash
rantaiclaw chat
```
Then, in the chat, paste your request with **all** settings spelled out:
```
Install nqrust-microvm on 10.0.0.5 over SSH (user ubuntu, password 's3cret').
Settings: Minimal mode, NAT networking, local PostgreSQL, default paths,
no container runtime, no Docker.
Connect, run preflight, launch the nqr-installer TUI in tmux, and drive it to
completion ONE KEY AT A TIME (wait for the screen to settle after each key).
Then run verify. Work autonomously; if you pause, I'll reply "continue".
```
When the agent pauses (input box returns), reply **`continue`**. Repeat until it reports
the install verified. If it ever shows a model tool-id error, type **`/retry`**.

> Give it **all** settings up front, or it will stop to ask — the skill gathers config
> conversationally by default.

### Approval prompts
`ssh`/`pty` are **always-ask** by default (a safety gate) — you approve each privileged
step with **Y**. For a hands-off run you can set `[autonomy] level = "full"` (no
prompts) — **only on a trusted/throwaway target**, and revert afterward.

---

## 5. What to expect — screen by screen

| Stage | Notes |
|---|---|
| Connect + **discovery** | ssh password/key auth; then it **detects specs + network** (CPU/RAM/disk/KVM, NICs/IP/gateway, virtualized?, ports, prior install) and **recommends a config** — install mode, NAT-vs-Bridged, Docker/runtime — grounded in the [docs](https://microvm.nexusquantum.id), and shows you the reasoning before proceeding |
| Welcome → **Mode** | **Minimal** (manager+agent) or Production (adds the Web UI) |
| **Network** | choose **NAT** — **not Bridged**. Bridged re-bridges the host's NIC and can **drop your SSH** mid-install |
| Configuration | path/DB defaults are fine; toggle Docker / Container-Runtime to *No* for a lighter, faster install |
| **Pre-flight Checks** | must be **all pass** — the **20 GB disk** check lives here |
| **Installation Progress** | the real work: ~10 min, downloads ~8 GB of base images. Hands-off |
| Verification → Complete | `nqrust-manager` / `nqrust-agent` / `postgresql` come up in the final phases |

The manager binds `:18080` a few seconds **after** its service goes active (it registers
the base images first), so don't panic if `/health` is briefly unreachable.

---

## 6. Verify

```bash
# on the target (or let the agent run the skill's verify.sh):
systemctl is-active nqrust-manager nqrust-agent postgresql   # → active active active
curl -fsS http://localhost:18080/health                      # → 200
ss -tlnp | grep -E ':(18080|9090|5432)'                      # manager / agent / postgres
```
Done → **Manager API** `http://<host>:18080`, **Web UI** `http://<host>:3000` (Production
mode only). Default login **root/root** — change it.

The agent also writes a **post-install report** (from `scripts/report.sh`): install mode,
component + firecracker versions, API health, bound ports, disk used by the image/VM stores,
the config you chose, and the access URLs. Keep it — it's the record of what got installed.

---

## 7. Operate it — create VMs from a prompt

Installation is half the job; the agent can also **run** the platform. The
**`nqrust-microvm-operate`** skill drives NQRust-MicroVM's own CLI, **`nqvm`**, over SSH against
the manager API. Just ask:

```bash
rantaiclaw agent -m "on <host> (ssh ubuntu, password ...): create a microVM named web, \
  2 vCPU, 1GB RAM, from the ubuntu-24.04 image; start it and show me its state"
```
```
list my VMs            stop web / start web / pause web
snapshot web           deploy nginx:latest as a container
delete web             import an image from dockerhub
```

How it works (validated end-to-end against a live install):
- The agent ensures `nqvm` is on the host. **It isn't a published release asset yet**, so the
  skill builds it locally and pushes it:
  ```bash
  # in the NQRust-MicroVM repo, once:
  cargo build --release --target x86_64-unknown-linux-musl -p nqvm-cli
  # → target/x86_64-unknown-linux-musl/release/nqvm   (the agent scp's this to the host)
  ```
- It logs in (`nqvm login --username root --password root`; **change these**), then resolves your
  names to UUIDs (`nqvm vm list --output json`) and runs the lifecycle commands.
- **Create a VM** needs a rootfs + a kernel image — the agent picks them from `nqvm image list`
  (e.g. `ubuntu-24.04-minimal` + `firecracker-v5.10`), then `nqvm vm create … && nqvm vm start`.
- **Destructive ops** (`vm delete`, etc.) take `--yes` and the agent confirms with you first.

For a serial console into a VM, the agent uses `pty` to drive `nqvm vm shell <id>`.

---

## 8. Troubleshooting (things we actually hit)

| Symptom | Cause / fix |
|---|---|
| Installer Pre-flight `✗ Disk Space … need 20GB+` | Give the host **≥ 30 GB free**. |
| SSH drops during install | You picked **Bridged**; it re-bridged the single NIC. Use **NAT**. |
| `tool id … not found (2013)` / model `400` | Strict provider (MiniMax). Type **`/retry`**; or use OpenRouter/Anthropic. |
| `402 Payment Required` / "can only afford N tokens" | Out of provider credits — top up. |
| Agent stops after a few steps | That's one-shot `agent -m`. Use **`rantaiclaw chat`** + "continue". |
| `no tmux session` | The agent must `pty start` first; `tmux` is installed on the target by preflight. |
| Manager `:18080` not up right after install | It registers base images (~30 s) then binds. Wait, re-check `/health`. |
| Network screen won't switch mode | The Bridged interface panel can hold focus; the modes are **Bridged, NAT, Isolated** (NAT is **Down** from Bridged), and `Tab` switches panels. |
| **Operate:** `nqvm: command not found` | Not a release asset yet — build `nqvm-cli` and let the agent push it (TUTORIAL §7). |
| **Operate:** `nqvm` says unauthorized / 401 | Run `nqvm login --username root --password root` first; token caches in `~/.config/nqvm/`. |
| **Operate:** `vm create` rejected | It needs **both** a rootfs **and** a kernel image id — `nqvm image list --kind rootfs` / `--kind kernel`. |
| **Operate:** `nqvm --version` errors | There's no `--version` flag; use `nqvm --help` or `nqvm auth status` to probe. |

---

## Appendix A — spin a throwaway target

### KubeVirt (nested KVM)
Needs KubeVirt + CDI, a node with nested virt, and `host-passthrough` CPU:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata: { name: nqr-target, namespace: default }
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata: { name: nqr-target-root }
      spec:
        storage:
          accessModes: [ReadWriteOnce]
          resources: { requests: { storage: 30Gi } }   # ≥30Gi for the installer's disk check
          storageClassName: local-path
        source: { registry: { url: "docker://quay.io/containerdisks/ubuntu:24.04" } }
  template:
    metadata: { labels: { kubevirt.io/domain: nqr-target } }
    spec:
      domain:
        cpu: { cores: 4, model: host-passthrough }   # host-passthrough = nested KVM in the guest
        devices:
          disks:
            - { name: rootdisk, disk: { bus: virtio } }
            - { name: cloudinit, disk: { bus: virtio } }
          interfaces: [{ name: default, masquerade: {}, ports: [{ name: ssh, port: 22 }] }]
        resources: { requests: { memory: 4Gi } }
      networks: [{ name: default, pod: {} }]
      volumes:
        - { name: rootdisk, dataVolume: { name: nqr-target-root } }
        - name: cloudinit
          cloudInitNoCloud:
            userData: |
              #cloud-config
              hostname: nqr-target
              users:
                - { name: ubuntu, sudo: "ALL=(ALL) NOPASSWD:ALL", shell: /bin/bash, lock_passwd: false, plain_text_passwd: rantai }
              ssh_pwauth: true
              chpasswd: { expire: false }
              growpart: { mode: auto, devices: ['/'] }   # expand root to the full 30Gi
              resize_rootfs: true
              packages: [curl, tmux, ca-certificates]
```
```bash
kubectl apply -f vm.yaml
# wait for it, then get its pod-network IP (reachable from the node):
kubectl get vmi nqr-target -o jsonpath='{.status.interfaces[0].ipAddress}'
# SSH: ubuntu / rantai
```

### multipass (simplest if you have it)
```bash
multipass launch 24.04 --name nqr-target --cpus 4 --memory 8G --disk 40G
multipass exec nqr-target -- bash -lc 'test -e /dev/kvm && echo kvm-ok'   # must print kvm-ok
multipass info nqr-target | grep IPv4
```

---

That's it — point the agent at the target's IP (step 4) and drive it to a verified
install. See `skill/nqrust-microvm/RUNBOOK.md` for deeper reference.
