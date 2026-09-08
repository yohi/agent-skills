# Setup Approach Decision Guide

After investigating the repository, choose the Human → Agent setup handoff
architecture that best matches the existing setup assets. Do not invent a new
architecture when an existing one is sufficient.

## Decision dimensions

| Dimension | Question to answer |
|---|---|
| **Setup audience** | Is this primarily end-user installation, contributor/developer setup, or both? |
| **Existing installer** | Does a deterministic installer or script already exist? |
| **Existing docs** | Are install docs mature and up to date, fragmented, duplicated, or missing? |
| **Existing agent config** | Is there already an `AGENTS.md`, `.opencode/`, or `CLAUDE.md`? |
| **Credential sensitivity** | Does setup require secrets or authentication? |
| **Platform support** | Which OS / architecture / runtime does the repo officially support? |

## Approach taxonomy

### A. Human README → existing installer (best when a good installer exists)

Use when the repo already has a reliable installer or bootstrap script.

- Keep the README install section as the canonical source of truth.
- Add a short README section that tells users they can paste a prompt into an
  AI coding agent; the agent should run the existing installer and verify it.
- Do not duplicate install commands into an Agent-specific file.

Example paste prompt:

```text
Set up https://github.com/org/repo for local development. Read README.md,
follow the canonical installation instructions, ask before any privileged or
destructive operation, and verify by running the test command.
```

### B. Human README → dedicated Agent setup protocol (best when no installer exists)

Use when the repo has manual install docs but no deterministic script.

- Write a dedicated Agent setup protocol, preferably as a new section in
  `AGENTS.md` (or a standalone file only if `AGENTS.md` does not exist or
  cannot be merged non-destructively).
- The protocol must reference the README / install docs as the canonical source;
  do not copy install commands into the protocol.
- Keep the protocol concise: starting state, decisions the Agent may make
  autonomously, questions that require structured Ask, verification steps,
  and failure recovery.

### C. Agent protocol → deterministic setup script (best when repeated setup is expected)

Use when the repository will be set up many times by agents and a script would
reduce variability.

- Add a script such as `scripts/agent-setup.sh` or an npm/poetry/Makefile target.
- The script must be runnable by a human too, so it remains a valid manual
  fallback.
- The Agent protocol in `AGENTS.md` should invoke the script, then run
  repository-defined verification commands.

### D. Common protocol with user / developer branches (best when the two paths differ)

Use when prerequisites, dependencies, authentication, or verification differ
substantially between end-user install and contributor setup.

- Define a common preamble (repo identification, capability detection, secret
  policy) and then branch into `user install` and `developer setup` tracks.
- Each track references its own canonical source: user docs for installation,
  `CONTRIBUTING.md` for developer setup.

### E. Agent-specific adapter → vendor-neutral protocol (best when multi-agent support matters)

Use when the repository is likely to be used by Claude, Cursor, OpenCode, and
  Antigravity users.

- Keep the common setup contract in a vendor-neutral file (`AGENTS.md` or
  `AGENT_SETUP.md`).
- Add thin adapter notes only when necessary (for example, how to invoke
  structured Ask on a specific platform). Refer to
  [agent-capability-matrix.md](agent-capability-matrix.md) for mappings.

## Default selection heuristic

1. If `Makefile` or `package.json` scripts already define `install`/`test`,
   prefer **A** and reuse them.
2. If there is no deterministic install command but install docs are present,
   prefer **B**.
3. If the repo is a CLI/tool that many users will install, or if setup is
   complex, prefer **C**.
4. If user install and developer setup clearly differ, prefer **D**.
5. If the repo explicitly targets multiple agent platforms, prefer **E**; for
   single-platform repos, avoid the extra adapter complexity.

## YAGNI rule

Do **not** add a wrapper script, preflight command, or deterministic installer
when the repository already provides:

- a package manager with install/test scripts (`npm install`, `npm test`)
- a Makefile with install/test targets
- a documented one-command install path
- CI that exercises the install path

Agent inspection plus the existing command surface is sufficient in those
cases. Adding a wrapper only creates a second thing to maintain.

## Anti-patterns

- **Template creep**: Do not force every repo into the same file layout.
- **Setup logic duplication**: Do not copy `npm install`, `pip install`, etc.
  into Agent-specific docs. Reference the canonical source.
- **Agent-only operation**: Do not make the Agent flow the only way to set up
  the repo. Always preserve a manual fallback.
- **Wrapper bloat**: Do not add `agent:setup`, `scripts/agent-setup.js`, or
  similar wrappers for small repos whose existing scripts are already clear.
