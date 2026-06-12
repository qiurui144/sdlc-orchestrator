# Install & Bootstrap

> [中文文档 — README.zh.md](../README.zh.md) | [Back to README](../README.md)

This guide covers installing **sdlc-orchestrator** into Claude Code, verifying the install, and bootstrapping a new repo with SDLC commands.

---

## Prerequisites

| Tool | Min version | Purpose |
|------|-------------|---------|
| bash | ≥ 3.2 | All skill/hook scripts |
| git | ≥ 2.20 | Repo detection, SHA hashing |
| jq | ≥ 1.6 | Hook JSON parsing |
| yq | ≥ 4.0 | YAML validation in handoff-schema |
| bats-core | ≥ 1.9 | Running the test suite (dev only) |

### Install commands

**macOS (Homebrew)**
```bash
brew install bash git jq yq
brew install bats-core          # dev only
```

**Ubuntu / Debian**
```bash
sudo apt-get update
sudo apt-get install -y bash git jq
sudo snap install yq             # or: pip install yq
# bats-core: see https://bats-core.readthedocs.io/en/stable/installation.html
```

**Arch Linux**
```bash
sudo pacman -S bash git jq yq
yay -S bats                      # AUR, dev only
```

**Version check**
```bash
bash --version | head -1
git --version
jq --version
yq --version
bats --version      # dev only
```

---

## Install plugin

### Option 1 — Marketplace (v0.2+, recommended)

In Claude Code, run:
```
/plugin install sdlc-orchestrator
```

### Option 2 — Manual clone

```bash
mkdir -p ~/.claude/plugins
git clone https://github.com/qiurui144/sdlc-orchestrator \
    ~/.claude/plugins/sdlc-orchestrator
```

### Option 3 — Dev symlink (for contributors)

```bash
# Clone anywhere you like:
git clone https://github.com/qiurui144/sdlc-orchestrator ~/dev/sdlc-orchestrator

# Symlink into the plugins directory:
mkdir -p ~/.claude/plugins
ln -s ~/dev/sdlc-orchestrator ~/.claude/plugins/sdlc-orchestrator
```

The symlink approach means edits in `~/dev/sdlc-orchestrator` are reflected immediately
without re-installing.

---

## Verify install

1. Confirm `plugin.json` is present:
   ```bash
   ls ~/.claude/plugins/sdlc-orchestrator/plugin.json
   ```

2. Restart Claude Code (or reload plugins with `/plugin reload` if available).

3. Run the health check command:
   ```
   /sdlc:status
   ```
   Expected output includes the plugin name, version, and detected stack (or `generic` if no
   project is open).

---

## Bootstrap a new repo

After installing the plugin, use it with any git repository:

1. **Navigate to your project root**
   ```bash
   cd /path/to/your/project
   ```

2. **Run `/sdlc:status`** — auto-detects stack (rust / ts / python / go / generic) and reports
   current SDLC phase state.

3. **Start a new sprint** with `/sdlc:spec <slug>`:
   ```
   /sdlc:spec user-auth
   ```
   This creates `docs/superpowers/specs/YYYY-MM-DD-user-auth.md` with all 11 §3.1 sections
   and awaits your review.

From there, proceed through the SDLC phases in order:
`spec` → `plan` → `impl` → `review` → `test` → `release`

---

## Uninstall

```bash
rm -rf ~/.claude/plugins/sdlc-orchestrator
```

State files created by the plugin (handoffs, specs, plans) remain in your project repos under
`docs/superpowers/`. Remove them manually if desired:
```bash
rm -rf docs/superpowers/
```

---

## Troubleshooting

### `yq: command not found`
Install yq v4+. On many systems `pip install yq` installs a Python-based yq v3 (incompatible).
Verify: `yq --version` must show `v4.x`. If not, use the Snap or binary install:
```bash
sudo snap install yq
# or download binary: https://github.com/mikefarah/yq/releases
```

### `bats: syntax error` or `unexpected token`
Ensure bats-core ≥ 1.9 is installed. The legacy `bats` 0.x package on some distros is
incompatible. Install via the bats-core repository directly:
```bash
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
```

### Hooks not firing (writes, Bash commands pass through unchecked)
1. Confirm hooks are registered: `cat ~/.claude/plugins/sdlc-orchestrator/hooks.json`
2. Verify Claude Code version supports `PreToolUse` / `PostToolUse` hooks (requires CC v0.2+).
3. Check the hook scripts are executable:
   ```bash
   ls -la ~/.claude/plugins/sdlc-orchestrator/hooks/*.sh
   chmod +x ~/.claude/plugins/sdlc-orchestrator/hooks/*.sh
   ```

### `/sdlc:status` returns `stack: generic` for a Rust project
Ensure `Cargo.toml` exists at the project root (not only in a workspace subdirectory).
The stack detector checks `$PWD/Cargo.toml`.
