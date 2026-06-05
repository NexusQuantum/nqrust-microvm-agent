---
name: nqrust-microvm-operate
description: Operate a running NQRust-MicroVM host from natural language — create/start/stop/delete microVMs, deploy containers & functions, manage images/networks/volumes/snapshots — by driving the product's own `nqvm` CLI over SSH against the manager API. Use AFTER nqrust-microvm is installed.
version: 0.1.0
tags: [microvm, firecracker, nqvm, cli, ssh, operations, day2]
---

# NQRust-MicroVM operations (day-2, via the `nqvm` CLI)

You operate an **already-installed** NQRust-MicroVM host: create and manage microVMs,
containers, serverless functions, images, networks, volumes, and snapshots. You do this by
driving the product's official CLI — **`nqvm`** — over SSH. `nqvm` is a thin client for the
**manager API** (`:18080`); every command is one HTTP call, so this is safe to run
non-interactively and easy to verify.

> Installing from scratch instead? Use the **`nqrust-microvm`** skill first. This skill assumes
> the manager is up (`curl :18080/health` → `{"status":"ok"}`).

## Tools

- **`ssh`** — transport. `connect` → `exec` (run `nqvm …`) / `push` (deliver the binary) /
  `disconnect`. Contracts identical to the `nqrust-microvm` skill.
- **`pty`** — ONLY for `nqvm vm shell <id>` (an interactive serial console). Everything else is
  plain `ssh exec`.

**Run `nqvm` ON the host** (via `ssh exec`). The manager listens on the host's `127.0.0.1:18080`,
so the CLI talks to it locally — no ports need to be exposed to you.

## Setup (once per host, per session)

1. **Connect**: `ssh connect {host, user, auth}` → session id.
2. **Ensure the binary**: `ssh push` `scripts/ensure-nqvm.sh` → `ssh exec "bash /tmp/ensure-nqvm.sh /tmp/nqvm"`.
   - exit 0 → reads `NQVM=/tmp/nqvm` (the path to use).
   - **exit 10** (not installed, no release asset yet) → **push a local build**:
     `ssh push {local_path:"<repo>/target/x86_64-unknown-linux-musl/release/nqvm", remote_path:"/tmp/nqvm"}`
     then `ssh exec "chmod +x /tmp/nqvm"`. (Build it with
     `cargo build --release --target x86_64-unknown-linux-musl -p nqvm-cli` in the NQRust-MicroVM
     repo if you don't have one. `nqvm` is **not** yet a published release asset.)
   - From here, call it as `NQVM=/tmp/nqvm` (use the path ensure-nqvm reported).
3. **Authenticate**: `ssh exec "/tmp/nqvm login --api-url http://127.0.0.1:18080 --username <u> --password <p>"`.
   - Default credentials are **`root` / `root`** — use them only if the operator hasn't changed
     them, and **remind the operator to change them**. Pass real creds via tool args; never print them.
   - The token is cached in `~/.config/nqvm/config.toml` on the host, so later commands don't
     re-auth. Confirm with `ssh exec "/tmp/nqvm auth status"`.
   - `nqvm` has **no `--version`** flag — probe liveness with `--help` or `auth status`.

## Golden rules

- **List before you act.** Almost every command targets a **UUID**, not a name. To act on
  "the web VM", first `nqvm vm list --output json`, find the item whose `name` matches, use its
  `id`. Same for images/networks/volumes. Use **`--output json`** whenever you need to parse;
  the default is a human table (good for showing the operator).
- **Confirm destructive actions.** `delete` (vms, images, networks, volumes, snapshots,
  functions, containers, hosts) is irreversible and takes `--yes`. Never delete, or delete-then-
  recreate, without an explicit operator OK. Stop a VM before deleting it.
- **Show, then do.** For create/deploy, echo the resolved settings (name, vCPU, mem, which
  image, which network) and get a go-ahead, then run the command and report the new `id` + state.
- **Secrets:** never print the login password or the cached token.

## Command reference (`nqvm <group> <verb>`)

Global flags (any command): `--api-url <url>` · `--token <t>` · `--output table|json` · `--config <path>`.

| Group | Verbs | Notes |
|---|---|---|
| *(top)* | `login --username --password [--api-url]` · `logout --yes` · `auth status` | token → `~/.config/nqvm/config.toml` |
| `vm` | `list` · `get <id>` · `create …` · `update <id>` · `start <id>` · `stop <id>` · `pause <id>` · `resume <id>` · `delete <id> --yes` · `shell <id> [--no-credentials]` | lifecycle; `shell` is interactive (pty) |
| `image` | `list [--kind rootfs\|kernel] [--name] [--project]` · `get <id>` · `create …` · `delete <id> --yes` · `dockerhub-search <q> [--limit]` · `dockerhub-tags <img>` · `dockerhub-download <img>` · `dockerhub-progress <img>` · `preload` | rootfs/kernel registry; DockerHub import |
| `container` | `list` · `get <id>` · `deploy …` · `update <id>` · `start/stop/restart/pause/resume <id>` · `delete <id> --yes` | OCI containers (needs container runtime installed) |
| `function` | `list` · `get <id>` · `create …` · `update <id>` · `invoke …` · `delete <id> --yes` | serverless (bun/python runtimes) |
| `network` | `list` · `get <id>` · `create …` · `update <id>` · `delete <id> --yes` · `suggest --host-id` · `interfaces --host-id` · `retry <id>` · `vms <id>` | NAT/bridged/isolated/vxlan; `suggest`/`interfaces` help pick a CIDR/uplink |
| `volume` | `list` · `get <id>` · `create …` · `attach <id> --vm-id --drive-id` · `detach <id> --vm-id` · `delete <id> --yes` | extra block devices |
| `snapshot` | `list --vm-id` · `get <id>` · `create --vm-id [--name --snapshot-type]` · `instantiate <id> [--name]` · `delete <id> --yes` | save/restore VM state |
| `template` | `list` · `get <id>` · `create --file` · `update <id>` · `instantiate <id> [--name]` · `delete <id> --yes` | reusable VM specs |
| `host` | `list` · `get <id>` · `delete <id> --yes` | registered agents/workers |
| `storage-backend` | `list` / `get` / … | storage backends |
| `user` | `list` / … | accounts |
| `license` | `…` | licensing |

Any `create`/`deploy`/`update` also accepts `--file <json>` instead of flags (POST that JSON body).

## Recipes (validated against a live install)

**Create & boot a microVM** (the most common ask):
1. `nqvm image list --kind rootfs --output json` → pick a rootfs `id` (e.g. `ubuntu-24.04-minimal`).
2. `nqvm image list --kind kernel --output json` → pick the kernel `id` (e.g. `firecracker-v5.10`).
3. `nqvm vm create --name <name> --vcpu <n> --mem-mib <mib> --rootfs-image-id <rootfs> --kernel-image-id <kernel> [--rootfs-size-mb <mb>] [--network-id <net>] [--username --password] [--tags a,b]`
   → returns `{"id":"<vm>"}`. `--network-id` is optional (the manager applies a default).
4. `nqvm vm start <vm>` → `{"ok":true}`. Verify: `nqvm vm list` → `state=running`.
   - Report the new id, name, vcpu/mem, and state to the operator.

**Lifecycle:** `nqvm vm stop|pause|resume <id>`. **Delete:** stop first, then
`nqvm vm delete <id> --yes` (confirm with the operator).

**Shell into a VM** (interactive serial console — use `pty`, not `exec`):
`pty start {session:"vm", target:"<ssh session>", command:"/tmp/nqvm vm shell <id>"}`, then drive
it like a terminal (`pty send`/`screen`/`wait`); `pty stop` when done. `--no-credentials` skips
the injected login.

**Deploy a container:** `nqvm container deploy --name <n> --image <repo:tag> [--command <cmd>]
[--cpu-limit <f>] [--memory-limit-mb <mb>] [--restart-policy <p>]` → then `nqvm container start <id>`.
(Requires the install to have the container runtime; if `image list` lacks `container-runtime`,
that wasn't installed.)

**Run a serverless function:** `nqvm function create --name <n> --runtime <bun|python> …`, then
`nqvm function invoke <id> [--file payload.json]`.

**Import an image from DockerHub:** `nqvm image dockerhub-search <query>` →
`nqvm image dockerhub-tags <image>` → `nqvm image dockerhub-download <image>` (poll
`nqvm image dockerhub-progress <image>`), then it appears in `nqvm image list`.

**Create a network:** `nqvm network suggest --host-id <h>` / `nqvm network interfaces --host-id <h>`
to see options, then `nqvm network create --name <n> --type <nat|bridged|isolated|vxlan>
--cidr <cidr> [--uplink-interface <if>] [--dhcp-enabled true] --host-id <h>`.

**Snapshot a VM:** `nqvm snapshot create --vm-id <vm> --name <n>`; restore with
`nqvm snapshot instantiate <snap> --name <new-vm>`.

**Status / report:** to summarize the whole install (services, versions, ports, URLs), run the
`nqrust-microvm` skill's `scripts/report.sh` on the host and present the result.

## Safety
- This drives a privileged platform API. Honor approval prompts; preview create/delete before running.
- Private LAN target IPs are expected and allowed by the `ssh` tool.
- Never echo the login password or the cached `nqvm` token. Warn about default `root/root`.
- Multi-host: each `ssh connect` is its own session; point `nqvm` at that host's local manager.
