---
name: agent-driven-setup
description: Introduces an Agent-driven setup framework into a GitHub or local repository. Use whenever the user wants to make a repository installable or developable by an AI coding agent from a short paste prompt, add an AI setup handoff to README, make an existing installer Agent-friendly, or redesign onboarding for Agent consumption. Do not use for one-shot "set up this repo on my machine" requests, generic CI/quality-only improvements, temporary-credential-only tasks, or unrelated HR/organization onboarding.
---

# Agent-driven Setup

Introduce an **Agent-driven setup framework** into a target repository so that
users can hand off installation or developer setup to an AI coding agent with a
short prompt.

The framework must be:
- **Adaptive**: shaped by the repository's existing setup assets, not a fixed template.
- **Non-destructive**: existing manual instructions, CI, and agent configuration are preserved.
- **Bootstrapable**: the Human entry point leads to a stable, canonical setup source.
- **Independent**: after introduction, the target repository does not depend on this meta-skill or `yohi/agent-skills`.
- **Verified**: the actual setup path is exercised where practical, not just documented.

## When to use this skill

Use this skill when the user asks to:
- Add an Agent-driven setup framework / protocol to a repository.
- Make a README install section usable by an AI coding agent.
- Make a repository "Agent-friendly" or "AI-runnable" for setup.
- Convert existing installer / setup docs into a Human → Agent handoff.
- Add a developer onboarding path that an AI coding agent can run autonomously.

Do **not** use this skill when:
- The user only wants a one-time local setup (`set up this repo on my machine`)
  with no intent to add reusable framework to the repository.
- The request is primarily about CI, linting, or quality/security tooling
  (`github-quality-setup` is the better fit).
- The request is only about using temporary cloud credentials
  (`temporary-credential-agent` is the better fit).

## Core workflow

### 1. Identify the target repository

- If a local checkout is already present, use it.
- If the user provides a GitHub URL, fetch what you can read (README, package
  metadata, CI files, directory tree). Do not claim to have implemented changes
  in a repository you cannot write to.

### 2. Investigate the repository before changing it

Run:

```bash
bash /mnt/skills/user/agent-driven-setup/scripts/analyze-repo.sh [repo-path]
```

Then cross-check the output against the checklist in
[references/repository-investigation-checklist.md](references/repository-investigation-checklist.md).
Do not rely on the README alone. Use CI, lockfiles, package metadata, scripts,
and actual commands to understand the setup contract.

### 3. Detect available agent capabilities

Probe the runtime environment for available tools. Map them to the generic
capabilities in
[references/agent-capability-matrix.md](references/agent-capability-matrix.md):

- `repository_inspection` (Read/Glob/Grep)
- `file_operations` (Write/Edit)
- `command_execution` (Bash)
- `structured_ask` (Ask / AskUserQuestion / equivalent)
- `secret_input` (masked / safe secret input)
- `web_fetch` (webfetch / browser fetch)

If capability detection is uncertain, assume `structured_ask` and `secret_input`
are **not** available and fall back safely.

### 4. Choose a setup approach

Use [references/setup-approach-decision-guide.md](references/setup-approach-decision-guide.md)
to choose one of:

- **A** — Human README → existing installer
- **B** — Human README → dedicated Agent setup protocol
- **C** — Agent protocol → deterministic setup script
- **D** — common protocol with user / developer branches
- **E** — agent-specific adapter → vendor-neutral protocol

Choose based on repository evidence, not preference. Reuse existing setup
assets. Do not duplicate setup logic.

**Default heuristic:**
1. If `Makefile` or `package.json` scripts already define `install`/`test`,
   prefer **A** and reuse them.
2. If there is no deterministic install command but install docs are present,
   prefer **B**.
3. If the repo is a CLI/tool that many users will install, or if setup is
   complex, prefer **C**.
4. If user install and developer setup clearly differ, prefer **D**.
5. If the repo explicitly targets multiple agent platforms, prefer **E**.

Do not add a wrapper script, preflight, or deterministic installer when the
repository's existing package-manager scripts and CI are already sufficient.
That is unnecessary overhead for small projects.

### 5. Create or update the Human entry point

Add a short section to the repository's `README.md` using the template in
[references/human-entry-point-template.md](references/human-entry-point-template.md).

The entry point must:
- Point to "this repository" and the canonical setup source, not a local-only
  or contributor-specific path.
- For remote / user-install cases, include the repository URL and the
  canonical setup source so a fresh Agent session can bootstrap without
  prior context.
- Remain short enough to paste into an AI coding agent.
- Preserve existing manual install instructions.

### 6. Create or merge the Agent setup protocol

The canonical protocol lives in the repository itself, ideally as a section
in `AGENTS.md` (or a standalone file only if `AGENTS.md` cannot be merged
non-destructively).

The protocol must:
- Reference existing setup assets as the **single canonical source of truth**.
  Treat README / install docs / CI / package metadata as supporting evidence or
  executable corroboration, not as parallel authorities.
- Use generic capability names, not vendor-specific tool names, in the common
  contract.
- List decisions the Agent may make autonomously and decisions that require
  structured Ask.
- State the secret policy (see
  - Include verification steps (see
  [references/verification-patterns.md](references/verification-patterns.md)).
- Follow the template in
  [references/agent-protocol-template.md](references/agent-protocol-template.md),
  which requires listing `repository_inspection`, `command_execution`,
  `structured_ask`, and `secret_input` as the generic capability contract.
- Not reference this meta-skill, `yohi/agent-skills`, or any external skill
  path.

If an existing `AGENTS.md`, `CLAUDE.md`, or `.opencode/` config exists, merge
non-destructively. If the existing guidance conflicts semantically with the
new setup framework (for example, an existing rule says "Never run npm install
automatically" while the new framework would run it autonomously), stop and
ask the user before overriding it.

### 7. Verify the setup path

Run:

```bash
bash /mnt/skills/user/agent-driven-setup/scripts/verify-setup.sh [repo-path]
```

This emits a verification plan that classifies each repository-defined command
as `safe`, `review`, or `dry-run-only`. Then:

- Run `safe` commands directly (e.g., `npm test`, `cargo test`).
- Use dry-run options for `review` commands when available.
- Ask the user before running commands that may mutate external state.
- Do not create paid production resources, production data, or unnecessary
  cloud infrastructure just for verification.

If setup verification is not possible in the current environment, report it as
**unverified**, not as success.

### 8. Report results

Return a completion report with:

- Selected setup approach and rationale.
- Human entry point text and location.
- Canonical setup source and corroborating evidence.
- Changed / added files.
- Reused existing setup assets.
- Verification results and any unverified items.
- Rerun verification status.
- CI changes.
- Agent E2E status (or "Agent E2E: Not verified" if unavailable).
- Known limitations.
- If the user supplied a canary / marker value to include in the README paste prompt only, do not copy that value into `AGENTS.md`, the final report, `summary.json`, or `transcript.md`.

## Safety invariants

### Structured Ask

If the Agent must wait for a user answer to continue, use a structured Ask
capability when available. Required gates include:

- Execution approval
- Setup mode selection (user install vs. developer setup)
- Account / project / region / organization selection
- Authentication initiation
- Paid operation
- External resource creation
- Privileged or destructive operation
- Machine-global modification
- **Semantic conflict with existing configuration**
- Missing free-form input needed to continue

If structured Ask is unavailable, fall back to plain chat only for required
questions and record the fallback.

Ordinary repo-local setup steps such as dependency installation, build, test,
and lint do not require Ask when the user has already delegated setup to the
agent. Ask only where the user's intent, risk, or an existing conflict cannot
be inferred from the repository.

### Secret handling

- Never ask for a secret value in normal chat.
- Do not treat a structured Ask as automatically secret-safe.
- Prefer official login flows, existing credential stores, terminal non-echo
  input, repository-official local env files, and temporary environment
  variables, in that order.
- Do not present a command-line literal such as `export API_KEY='<your-key>'`
  as the primary secret input method, because it encourages pasting secrets
  into shell history.
- Use secrets without observing them whenever possible.
- Redact secret-bearing output before it enters the Agent context.
- Confirm `.gitignore` excludes real env files before creating them.

See [references/secret-handling-patterns.md](references/secret-handling-patterns.md)
for concrete patterns.

### Risk-based execution

Autonomously execute reversible repo-local operations such as:

- repository inspection
- repo-local file creation / modification
- dependency installation
- build / test / lint
- non-destructive verification
- local development setup

Gate privileged, destructive, paid, or externally impactful operations with
structured Ask (or a documented safe fallback if unavailable).

### Repository mutation safety

- Do not delete unrelated user changes.
- Do not `git reset --hard` or force-clean a dirty working tree.
- Do not stash user changes without permission.
- Do not format or rewrite unrelated files.
- Do not turn existing local configuration into a clean slate.
- Do not commit, push, or create PRs unless the user explicitly asks.

### Existing-state safety

Assume the environment may already be partially set up. Consider:

- already installed dependencies
- old versions
- existing `.env`
- existing agent config
- existing credentials
- previously run installer
- generated files already present

Run setup-related commands a second time when practical to detect duplicate
configuration, repeated append, or destructive overwrite. If full idempotency
is impossible, state the conditions explicitly.

## Common mistakes to avoid

| Mistake | Correct response |
|---|---|
| Duplicating `npm install` / `pip install` into an Agent-specific file | Reference the README / CI / script as the canonical source. |
| Overwriting an existing `AGENTS.md` | Merge non-destructively or ask before replacing. |
| Asking the user for a package manager or test command | Infer these from repository evidence. |
| Treating "I edited the docs" as verified setup | Run repository-defined build / test / lint commands. |
| Embedding a real or synthetic secret in a report or generated file | Redact or omit; verify capability, not value. |
| Making Agent setup the only way to install the repo | Preserve manual fallback. |
| Referencing `yohi/agent-skills` in generated files | Generated framework must be self-contained. |
| Adding `npm run agent:setup` preflight to a small repo with existing scripts | Agent inspection is sufficient; avoid wrapper bloat. |
| Presenting `export KEY='<value>'` as the primary secret input | Prefer non-echo terminal input or credential store. |

## Reference files

- [references/repository-investigation-checklist.md](references/repository-investigation-checklist.md) — what to inspect before changing anything.
- [references/setup-approach-decision-guide.md](references/setup-approach-decision-guide.md) — how to choose a setup architecture.
- [references/agent-capability-matrix.md](references/agent-capability-matrix.md) — generic capabilities and concrete tool mappings.
- [references/secret-handling-patterns.md](references/secret-handling-patterns.md) — safe secret input, redaction, and verification.
- [references/verification-patterns.md](references/verification-patterns.md) — dry-run, local mode, smoke tests, and failure reporting.
- [references/human-entry-point-template.md](references/human-entry-point-template.md) — paste-ready README section template.
