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
Set up this repository for local development. Read <CANONICAL_SETUP_SOURCE>,
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
Set up https://github.com/org/repo from this repository. Read
<CANONICAL_SETUP_SOURCE> as the canonical setup source, follow its installation
instructions, ask before any privileged or destructive operation, and verify by
running the test command.
```
````

## Why this shape

- **Short**: The user only pastes a prompt; the agent does the reading.
- **Stable**: It points to the repository URL and canonical documentation, not
  to a contributor-specific path or ephemeral branch.
- **Bootstrapable**: A fresh Agent session can identify the target repository
  and reach the canonical setup source from the prompt alone.
- **Fallback**: Manual install instructions remain intact elsewhere in the
  README.

## Customization

Replace `<CANONICAL_SETUP_SOURCE>` in each generated prompt with the actual
canonical setup source path selected after running `analyze-repo.sh`. Do not
leave a fixed `README.md` or `AGENTS.md` reference when another source was
selected; use the standalone protocol file path when `AGENTS.md` cannot be
merged. If the repository has separate user install and developer setup tracks,
customize each prompt with its own canonical source.

If the user supplied a canary or marker value to include in the prompt, place it
inside the prompt block only. Do not copy that value into `AGENTS.md`, the final
report, `summary.json`, or `transcript.md`.
