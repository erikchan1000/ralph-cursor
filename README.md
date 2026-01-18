# ralph-cursor

Portable Ralph CLI scripts for macOS and Linux. These scripts run Cursor's agent locally with token-aware streaming, context rotation, and simple UX.

## Installation

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/main/install.sh | bash
```

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

### Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                      ralph-setup.sh                         │
│                           │                                 │
│              ┌────────────┴────────────┐                   │
│              ▼                         ▼                   │
│         [gum UI]                  [fallback]               │
│     Model selection            Simple prompts              │
│     Max iterations                                         │
│     Options (branch, PR)                                   │
│              │                         │                   │
│              └────────────┬────────────┘                   │
│                           ▼                                 │
│    cursor-agent -p --force --output-format stream-json      │
│                           │                                 │
│                           ▼                                 │
│                   stream-parser.sh                          │
│                      │        │                             │
│     ┌────────────────┴────────┴────────────────┐           │
│     ▼                                           ▼           │
│  .ralph/                                    Signals         │
│  ├── activity.log  (tool calls)            ├── WARN at 70k │
│  ├── errors.log    (failures)              ├── ROTATE 80k  │
│  ├── progress.md   (agent writes)          ├── COMPLETE    │
│  └── guardrails.md (lessons learned)       └── GUTTER      │
│                                                             │
│  When ROTATE → fresh context, continue from git            │
└─────────────────────────────────────────────────────────────┘
```

## CLI flags

- ralph-loop.sh
  - `-n, --iterations N`: Max iterations (default: 20)
  - `-m, --model MODEL`: Model to use (default: opus-4.5-thinking; or set `RALPH_MODEL`)
  - `--branch NAME`: Create/use branch for work
  - `--pr`: Open a PR when complete (requires `--branch`)
  - `-y, --yes`: Skip confirmation prompt
  - `-h, --help`: Show help
  - Positional: `[workspace]` (path to project; defaults to current directory)
  - Env:
    - `RALPH_MODEL` (same as `-m`)
    - `RALPH_AGENT_BIN` (`cursor-agent` or `agent`, default: `cursor-agent`)
    - `MAX_ITERATIONS`

- ralph-once.sh
  - `-m, --model MODEL`: Model to use (default: opus-4.5-thinking; or set `RALPH_MODEL`)
  - `-h, --help`: Show help
  - Positional: `[workspace]` (path to project; defaults to current directory)
  - Env:
    - `RALPH_MODEL`
    - `RALPH_AGENT_BIN`

- ralph-setup.sh
  - Positional: `[workspace]` (path to project; defaults to current directory)
  - Interactive options provided via gum or prompt:
    - Model selection
    - Max iterations
    - Options: commit to current branch, run single iteration first, work on new branch, open PR when complete
  - Env:
    - `RALPH_MODEL`, `MAX_ITERATIONS`, `RALPH_AGENT_BIN` (optional overrides)

- init-ralph.sh
  - No flags. Initializes `.ralph` structure and installs scripts under `.cursor/ralph-scripts/` in the target project.

