# ralph-cursor

Portable Ralph CLI scripts for macOS and Linux. These scripts run Cursor's agent locally with token-aware streaming, context rotation, and simple UX.

## Installation

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/erikchan1000/ralph-cursor/master/install.sh | bash -s -- --install-deps
```

Note: The installer places all Ralph scripts under `.cursor/ralph-scripts/` in your project directory (creating `.cursor` if needed).

## Layout

- `scripts/ralph-setup.sh` — Interactive setup + run loop (gum UI if available)
- `scripts/ralph-loop.sh` — Non-interactive loop runner (CLI flags)
- `scripts/ralph-once.sh` — Single iteration, for quick tests
- `scripts/ralph-common.sh` — Shared logic (loop, prompt, helpers)
- `scripts/stream-parser.sh` — Parses `--output-format stream-json` from the agent
- `scripts/init-ralph.sh` — Bootstraps `.ralph` files in a project

(When installed into a project, these are available under `.cursor/ralph-scripts/`.)

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
./.cursor/ralph-scripts/ralph-setup.sh

# Or non-interactive loop
./.cursor/ralph-scripts/ralph-loop.sh -y

# Single iteration
./.cursor/ralph-scripts/ralph-once.sh
```

Monitor progress:

```bash
tail -f .ralph/activity.log
```

Note: During runs, updates are mirrored to your terminal in real time; tailing the log is optional.

## PRD (RALPH_TASK.md) conventions

- Location: place `RALPH_TASK.md` at the project root.
- Completion rule: the loop treats the task as complete when there are no unchecked checklist items remaining.
  - Counted items are markdown list entries that start with `-`, `*`, or `1.` etc. and contain `[ ]` or `[x]`, e.g. `- [ ] Implement foo`.
- Loop behavior tie-in: Ralph will read `RALPH_TASK.md`, then work on the next unchecked criterion (look for `[ ]`) and expects you/the agent to change it to `[x]` when done. This mirrors the prompt printed by the loop.
- Recommended structure:
  - Optional front matter:
    - `task`: short description of the task
    - `test_command`: command to validate success (e.g., `"npm test"`). The loop doesn’t execute it automatically; it’s a convention for humans/agents to follow.
  - Sections: Context/PRD (or Task), Goals, Non-goals, Constraints, Success Criteria (as checkboxes), Test Plan, and Notes.
- Visibility: the first ~30 lines of `RALPH_TASK.md` are printed at startup for quick context.

Example template:

```markdown
---
task: "Implement feature X end-to-end"
test_command: "npm test"
---

# PRD

## Context
Brief background and scope.

## Goals
- Clear user-facing goals.

## Non-goals
- Out-of-scope items.

## Constraints
- Tech or process limits.

## Success Criteria
1. [ ] Backend API implemented
2. [ ] Frontend UI implemented
3. [ ] E2E happy path works
4. [ ] Tests pass via "npm test"
```

Minimal example aligned with the loop prompt:

```markdown
---
task: "Tighten CI and fix flaky test"
---

# Task

## Success Criteria
1. [ ] Fix flaky test in api/users.test.ts
2. [ ] Add CI step to run tests on PR
3. [ ] Document steps in README

## Context
Link to failing runs and notes here.
```

## Example RALPH_TASK.md (from @python/RALPH_TASK.md)

```markdown
# PRD

- [x] Goal: Verify Ralph plugin installs via README one-liner.
- [x] Result: Installed scripts into .cursor/ralph-scripts successfully.
- [x] Next: Run ./.cursor/ralph-scripts/init-ralph.sh if needed.
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

