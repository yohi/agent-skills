# Agent Setup Protocol Template

Use this template as the starting shape for the Agent setup protocol that lives
in the target repository. Merge it non-destructively into the existing
`AGENTS.md` whenever possible.

## Required elements

1. **Canonical source of truth**: state which existing asset (README.md,
   package metadata, Makefile, CI, etc.) is the primary source for setup
   commands. Do not duplicate those commands.
2. **Generic capability contract**: list the four generic capabilities the agent
   may use:
   - `repository_inspection` (Read / Glob / Grep / directory listing)
   - `command_execution` (run shell commands in the working directory)
   - `structured_ask` (ask the user for approval or a choice)
   - `secret_input` (accept a secret through a safe, non-chat channel)
3. **Decision boundaries**: which decisions the agent may make autonomously and
   which require explicit user approval.
4. **Secret policy**: how to handle `API_KEY`, `.env`, and other credentials.
5. **Verification steps**: how to confirm the setup worked.

## Minimal protocol section

```markdown
## Agent-driven setup

The canonical setup source is `<PRIMARY_SOURCE>`.

When setup is requested:

1. Use `repository_inspection` to read the canonical source and inspect the
   working tree.
2. Use `command_execution` to run the setup commands defined by the canonical
   source. Reversible, repository-local commands may run without an additional
   approval.
3. Use `structured_ask` before privileged, destructive, machine-global,
   external, paid, or ambiguous operations. If unavailable, ask in plain chat
   and record the fallback.
4. Use `secret_input` (or a trusted terminal / credential store fallback) for
   any required secret. Never request or print secret values in normal chat.
5. Verify setup by running the repository-defined test command. If a step
   fails, report the non-secret output and next safe action.

Do not commit, push, or open a pull request unless the user explicitly asks.
```

## What to avoid

- Vendor-specific tool names such as `AskUserQuestion`, `Claude`, `Cursor`, or
  `OpenCode` in the common contract.
- Duplicating install / build / test commands as the primary source of truth.
- References to this meta-skill, `yohi/agent-skills`, or any external skill path.
- Requesting or persisting secret values.
