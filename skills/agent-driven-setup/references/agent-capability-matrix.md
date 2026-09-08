# Agent Capability Matrix

The generated setup framework must stay vendor-neutral in its common contract.
Use this matrix only when you need to map a generic capability to a concrete
tool name in an agent-specific adapter.

## Generic capabilities

| Capability | Meaning |
|---|---|
| `repository_inspection` | Read files, list directories, grep, glob |
| `file_operations` | Create, read, edit, move, delete repository-local files |
| `command_execution` | Run shell commands in the working directory |
| `structured_ask` | Ask the user a multiple-choice / yes-no / execution-approval question |
| `secret_input` | Accept a password or secret value through a safe, non-chat channel |
| `web_fetch` | Fetch public web content (e.g., a GitHub README) |

## Concrete tool mapping by platform

| Capability | Claude Code | Cursor | OpenCode | Antigravity |
|---|---|---|---|---|
| `repository_inspection` | `Read`, `Glob`, `Grep` | Built-in context / `@` files | `Read`, `Glob`, `Grep` | Context / file search |
| `file_operations` | `Write`, `Edit` | Inline edits | `Write`, `Edit` | File tools |
| `command_execution` | `Bash` | Terminal / command runner | `Bash` | `Bash` |
| `structured_ask` | `AskUserQuestion` / `Ask` | `AskUser` (if available) | `question` tool | Agent-specific |
| `secret_input` | `AskUserQuestion` with `secret` (when supported) | OS keychain / trusted terminal | `question` with masking (if supported) | Trusted terminal |
| `web_fetch` | `webfetch` | Browser / fetch | `webfetch` | Fetch / browse |

## Usage rule

1. Start by probing the actual environment for the concrete tools that are
   available. Do not assume a tool exists just because the platform normally
   provides it.
2. Map available tools to the generic capabilities above.
3. Write the setup contract using generic capability names.
4. Only reference concrete tool names inside agent-specific adapter notes,
   and clearly mark them as examples, not requirements.

## Capability detection fallback

If you cannot determine which tools are available:

- Assume `repository_inspection`, `file_operations`, and `command_execution`
  are available, because an AI coding agent minimally needs these.
- Assume `structured_ask` and `secret_input` are **not** available until proven.
- Fall back to plain chat for required questions, and to trusted-terminal
  instructions for secret input.
