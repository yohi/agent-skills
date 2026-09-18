# Skill Authoring Guide

Guidance for creating and editing skills in this repository. Read this before
adding or changing any skill under `skills/`, and follow it together with the
verification rules in [`AGENTS.md`](../AGENTS.md).

## Workflow

1. Create the skill directory and files (see the structure below).
2. Run `node scripts/validate-skills.js` from the repository root.
3. Fix any errors or warnings, then rerun until the output is clean.
4. Self-review the skill against the checklist below before committing.

## Directory structure

```text
skills/
  {skill-name}/           # kebab-case directory name
    SKILL.md              # Required: skill definition
    scripts/              # Optional: executable scripts
      {script-name}.sh    # Bash scripts (preferred)
```

## Naming conventions

- **Skill directory**: `kebab-case` (e.g. `web-quality`)
- **SKILL.md**: Always uppercase, always this exact filename
- **Scripts**: `kebab-case.sh` (e.g., `deploy.sh`, `fetch-logs.sh`)

## SKILL.md format

````markdown
---
name: {skill-name}
description: {One sentence describing what the skill does, followed by one or more "Use when" trigger conditions. Include trigger phrases like "Deploy my app" or "Check logs" when helpful.}
---

# {Skill Title}

{Brief overview of what the skill does and why it matters.}

## How It Works

{Numbered list explaining the skill's workflow}

Equivalent headings like `Workflow`, `Core Process`, or `When to Use` are fine
when they communicate the same structure clearly.

## Usage (Optional)

Include this section only if the skill ships runnable helpers under
`scripts/`. Markdown-only skills can omit both the section and the directory
entirely.

```bash
bash /mnt/skills/user/{skill-name}/scripts/{script}.sh [args]
```

**Arguments:**
- `arg1` - Description (defaults to X)

**Examples:**
{Show 2-3 common usage patterns}

## Output

{Show example output users will see}

## Present Results to User

{Template for how the agent should format results when presenting to users}

## Troubleshooting

{Common issues and solutions, especially network/permissions errors}
````

## Context efficiency

Skills are loaded on-demand — only the skill name and description are loaded
at startup. The full `SKILL.md` loads into context only when the agent decides
the skill is relevant. To minimize context usage:

- **Keep SKILL.md under 500 lines** — put detailed reference material in
  separate files
- **Write specific descriptions** — helps the agent know exactly when to
  activate the skill
- **Use progressive disclosure** — reference supporting files that get read
  only when needed
- **Prefer scripts over inline code** — script execution doesn't consume
  context (only output does)
- **File references work one level deep** — link directly from `SKILL.md` to
  supporting files

## Script requirements

- Use `#!/bin/bash` shebang
- Use `set -e` for fail-fast behavior
- Write status messages to stderr: `echo "Message" >&2`
- Write machine-readable output (JSON) to stdout
- Include a cleanup trap for temp files
- Reference the script path as
  `/mnt/skills/user/{skill-name}/scripts/{script}.sh`

## Self-review checklist

Before committing or deploying a new skill, self-review it against the official
[Anthropic Skill Authoring Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md)
using the checklist below:

- **Conciseness (Concise is Key)**
  - [ ] Does this skill avoid explaining concepts the agent already knows?
        (Keep `SKILL.md` under 500 lines.)
  - [ ] Are all instructions focused only on the domain-specific nuances?
- **YAML Metadata Rules**
  - [ ] Is the `name` lowercase alphanumeric with hyphens, under 64 characters,
        and free of reserved words ("anthropic", "claude")?
  - [ ] Is the `description` non-empty and under 1024 characters?
- **Point of View (Third-Person Description)**
  - [ ] Is the `description` written strictly in the third person? (e.g.,
        "Extracts text..." instead of "I can help you extract..." or "Use this
        to extract...").
- **Appropriate Degrees of Freedom**
  - [ ] Does the style match the task fragility? (High freedom for
        reviews/heuristics, low freedom/rigid scripts for fragile actions like
        database migrations.)
- **Progressive Disclosure & Link Depth**
  - [ ] Are detailed lists, references, and schemas stored in separate markdown
        files loaded only when needed?
  - [ ] Are all referenced files linked directly from `SKILL.md` (exactly one
        level deep, avoiding nested links like `SKILL.md` -> `advanced.md` ->
        `details.md`)?
- **Workflow & Feedback Loops**
  - [ ] For multi-step tasks, is there a validation feedback loop defined?
        (e.g., Run tool -> Check errors -> Fix -> Repeat.)
  - [ ] Are complex tasks accompanied by a progress checklist that the agent
        can copy and check off?
- **Consistent Terminology**
  - [ ] Are technical terms consistent throughout the skill (e.g., always
        "API endpoint" instead of mixing it with "URL" or "path")?
