# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot,
Antigravity, OpenCode, etc.) working in this repository.

A collection of self-managed agent skills for Claude.ai, Claude Code, and other
AI coding agents. Skills are packaged instructions and scripts that extend
coding agents with senior-engineer workflows.

## Skills-First Execution

- Skills live in `skills/<skill-name>/SKILL.md`.
- If a task matches a skill, you MUST invoke it before responding or
  implementing.
- Never implement directly if a skill applies, and follow the skill
  instructions exactly (do not partially apply them).
- Map user intent to a skill automatically. "This is too small for a skill" and
  "I'll gather context first" are not valid reasons to skip a matching skill.

## Verification Commands

Run from the repository root:

```bash
node scripts/validate-skills.js
```

Run `node scripts/validate-commands.js` as well when slash commands change.
Always run these after creating or changing any skill, and fix all errors and
warnings before committing.

## Skill Authoring

To create or edit a skill, first read
[docs/skill-authoring.md](docs/skill-authoring.md). It owns the directory
structure, naming conventions, `SKILL.md` format, context-efficiency rules,
script requirements, and the pre-commit self-review checklist.

## Scope

- `README.md` is the human entry point for project overview and quick start.
- This file is the canonical source for agent behavior in this repository; do
  not duplicate agent rules in the README or in individual skills.
