# Human Entry Point Template

Add a short section to the repository's `README.md` so users can hand off setup
to an AI coding agent. Keep it short and stable.

## Local / developer setup template

````markdown
## Set up with an AI coding agent

Copy and paste the prompt below into an AI coding agent (Claude Code, Cursor,
OpenCode, etc.). The agent will inspect the repository and your environment,
then run the appropriate setup steps.

```text
Set up this repository for local development. Read <CANONICAL_SETUP_SOURCE_PATH>,
follow its installation instructions, ask before any privileged or destructive
operation, and verify by running the test command.
```
````

## Remote / user-install template

When the user does not already have the repository cloned, include the URL
and the canonical source so a fresh Agent session can bootstrap:

````markdown
## Set up with an AI coding agent

Copy and paste the prompt below into an AI coding agent:

```text
Set up https://github.com/org/repo from this repository. First read
<CANONICAL_SETUP_SOURCE_RAW_URL> as the canonical setup source, then clone the
repository and follow its installation instructions. Ask before any privileged
or destructive operation, and verify by running the test command.
```
````

## Why this shape

- **Short**: The user only pastes a prompt; the agent does the reading.
- **Stable**: The remote prompt uses an immutable raw-content URL for canonical
  documentation, not a contributor-specific path, GitHub HTML page, or
  ephemeral branch.
- **Bootstrapable**: A fresh Agent session can identify the target repository
  and reach the canonical setup source from the prompt alone.
- **Fallback**: Manual install instructions remain intact elsewhere in the
  README.

## Customization

Replace `<CANONICAL_SETUP_SOURCE_PATH>` in local prompts with the actual
canonical setup source path selected after running `analyze-repo.sh`. Replace
`<CANONICAL_SETUP_SOURCE_RAW_URL>` in remote prompts with the corresponding
immutable raw-content URL, such as
`https://raw.githubusercontent.com/org/repo/<commit>/AGENTS.md`. Do not use a
relative path or a GitHub HTML (`blob`) URL in a remote prompt. Do not leave a
fixed `README.md` or `AGENTS.md` reference when another source was selected; use
the standalone protocol file path or raw URL when `AGENTS.md` cannot be merged.
If the repository has separate user install and developer setup tracks,
customize each prompt with its own canonical source.

If the user supplied a canary or marker value to include in the prompt, place it
inside the prompt block only. Do not copy that value into `AGENTS.md`, the final
report, `summary.json`, or `transcript.md`.
