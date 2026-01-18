# ralph-cursor

Portable Ralph CLI scripts for macOS and Linux. These scripts run Cursor's agent locally with token-aware streaming, context rotation, and simple UX.

## Layout

- `scripts/ralph-setup.sh` — Interactive setup + run loop (gum UI if available)
- `scripts/ralph-loop.sh` — Non-interactive loop runner (CLI flags)
- `scripts/ralph-once.sh` — Single iteration, for quick tests
- `scripts/ralph-common.sh` — Shared logic (loop, prompt, helpers)
- `scripts/stream-parser.sh` — Parses `--output-format stream-json` from the agent
- `scripts/init-ralph.sh` — Bootstraps `.ralph` files in a project

## Requirements

- bash 3.2+ (macOS default is fine)
- git
- `cursor-agent` (or compatible `agent`)
  - Install: `curl https://cursor.com/install -fsS | bash`
- `jq` (required by `stream-parser.sh`)
- `bc` (optional; improves token size display)
- `gum` (optional; for `ralph-setup.sh` UI)

### Install dependencies

macOS (Homebrew):

```bash
brew install jq bc gum
```

Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y jq bc
```

## Usage

From a project repo with `RALPH_TASK.md` and git:

```bash
# Interactive (recommended)
./scripts/ralph-setup.sh

# Or non-interactive loop
./scripts/ralph-loop.sh -y

# Single iteration
./scripts/ralph-once.sh
```

Monitor progress:

```bash
tail -f .ralph/activity.log
```

## Cross-platform notes

- `sed -i` differences handled via `sedi()` helper.
- No bash 4-only features (associative arrays avoided).
- Parser logs a clear error if `jq` is missing and exits gracefully.

## Environment overrides

- `RALPH_MODEL` — default model (e.g., `sonnet-4.5-thinking`)
- `RALPH_AGENT_BIN` — agent binary (`cursor-agent` by default, fallback to `agent`)
- `MAX_ITERATIONS` — loop iteration cap

