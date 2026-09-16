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
Set up https://github.com/org/repo for local development. First read
https://raw.githubusercontent.com/org/repo/0123456789abcdef0123456789abcdef01234567/README.md
as the canonical setup source. The raw URL must use a full 40-character commit
SHA, never a branch or tag. Clone the repository and check out the same commit
SHA before following the installation instructions. Ask before any privileged
or destructive operation, and verify by running the test command.
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

## Enhanced workflow for complex repositories

Some repositories expose enough complexity that a simple README → installer handoff
is not enough. In those cases use the Setup Contract v1 workflow instead of adding
a wrapper script.

Use the enhanced workflow when `analyze-repo.sh` reports complexity triggers such
as an MCP runtime (`mcp.json`), multiple configuration writers, or webhook URLs.
These triggers are evidence that the repository has more than one configuration
surface and that setup should be driven by an explicit Contract rather than by
heuristic command detection.

### Contract placement and discovery marker

The Contract is the YAML frontmatter of a single Markdown file. The Markdown body
is explanatory only. Place the Contract file at one of these locations:

- `SETUP-CONTRACT.md` at the repository root
- A Markdown file under `docs/`

Discovery starts from a marker in the repository root `AGENTS.md` or `README.md`:

```text
<!-- agent-setup-contract: path/to/contract.md -->
```

The marker must be a standalone line and the path must be a normalized
repository-relative path. Absolute paths, `..` components, and symlink escapes are
schema errors. The exact marker syntax is `<!-- agent-setup-contract:` followed
by the path and `-->`. If the marker is absent, the auditor scans candidate files
under the root and `docs/`.

### Discovery outcomes and next steps

`audit-contract.sh` reports one of these discovery states:

- `found`: a single Contract was discovered and its frontmatter is syntactically
  valid. Continue with schema and topology validation.
- `not_found`: no Contract was discovered. Return to the repository investigation
  / extraction step (the simple-repository path): run `analyze-repo.sh` and
  `verify-setup.sh` and use the standard approach taxonomy above.
- `ambiguous`: more than one marker or more than one candidate file was found, or
  the markers in `AGENTS.md` and `README.md` disagree. Stop and perform semantic
  review with the repository owner before continuing.
- `contract_error`: the declared Contract path is malformed, escapes the target
  root, or its frontmatter is not valid YAML. Fix the Contract and rerun the audit.

### What the Contract captures

The Contract records the setup intent, target type, configuration branches,
mutation surfaces, process runtime safety, verification probes, and handoffs.
Target types include `skill`, `mcp`, `plugin`, `hook`, `cli`, `service`, and
`other/custom`. Each target declares its canonical source and runtime mode.

Process runtime targets declare both `runtime.command` and `runtime.safety`. The
safety enum is `read_only`, `mutating`, or `unknown`;
  it is a declaration, not an
execution permit. Other runtime modes must not carry `command` or `safety`.

Configuration branches list layers in order. Each layer has a closed v1 `kind` such
as `choice`, `installer`, `cli`, `env`, `settings`, `generated_config`,
`registration`, `discovery`, `runtime_consumer`, `activation`,
`representative_operation`, or `verification`. Unknown kinds are schema errors.

Mutation surfaces live under `external_effects.mutation_surfaces`. Each surface
declares its scope (`repository`, `user_local`, `global`, or `external`), kind,
value, snapshot policy, and whether cleanup is required. Investigate these surfaces
before running any probe that could touch them.

### Probe Safety Policy v1 boundary

The Contract validates the shape of every probe and the safety enum, but safety
declarations do not authorize probe execution. The effective Probe Safety Policy
v1 and the argv classifier are owned by `run-target-probes.sh`. `audit-contract.sh`
performs no target-repository writes and never executes a probe.

For dry-run classification reuse the executor's `--classify-only` interface. Do
not reimplement the classifier inside `audit-contract.sh` or duplicate the policy
in the Contract schema document.

### P1 handoffs

Some verification items must be handled outside Spec 1:

- `agent_action` probes with `action: discovery` or `action: activation` are
  handed off to Skill discovery / activation. Spec 1 validates the adapter shape
  but does not perform the discovery.
- `mcp_request` probes that reference a Contract-defined `temporary_fixture`
  surface are handed off or reported as `safety_blocked` in P1. P1 accepts the
  surface declaration but does not automatically create or clean up the fixture.

### Simple-repository path is preserved

When `audit-contract.sh` returns `not_found`, or when `analyze-repo.sh` reports no
complexity triggers, continue using the existing standard flow: choose an approach
from the taxonomy above, create the Human entry point and Agent protocol, then run
`verify-setup.sh`. Do not force a Contract onto a repository whose existing
scripts and docs are already sufficient.

### Anti-patterns for the enhanced flow

- Creating a Contract for a repository that already has a clear README → installer
  path.
- Treating `runtime.safety: read_only` as permission to run a probe without the
  executor's policy check.
- Duplicating the Probe Safety Policy v1 or `--classify-only` logic in the Contract
  schema or audit script.
- Running `audit-contract.sh` with an output directory inside the target repository.
