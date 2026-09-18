# MCP Probe Handshake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every MCP stdio probe use the MCP 2025-06-18 initialization lifecycle and correctly account for notification messages.

**Architecture:** Keep the existing sequential subprocess loop in `run-target-probes.sh`. Represent each outbound wire message separately from its response expectation so `notifications/initialized` is written but never read as a response. Each probe mode creates its own complete handshake because `verify-setup.sh` launches each item in a new process.

**Tech Stack:** Bash test harness, embedded Python 3 probe executor, JSON-RPC 2.0 over MCP stdio.

## Global Constraints

- Send `protocolVersion: "2025-06-18"`, `capabilities: {}`, and deterministic `clientInfo` in every initialize request.
- Send `notifications/initialized` only after a valid initialize response.
- Use request IDs `1`, `2`, and `3` for initialize, tools/list, and tools/call respectively.
- Do not wait for or count a notification as a response.
- Preserve the existing read-only runtime gate, timeout behavior, evidence format, and error categories.
- Do not execute CodeRabbit CLI because no explicit authorization was provided.

---

### Task 1: Make MCP tests assert the real handshake

**Files:**
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh:2718-2890`

**Interfaces:**
- Consumes: `run-target-probes.sh` JSONL stdin/stdout protocol.
- Produces: protocol-aware fixtures and assertions for standalone initialize, tool discovery, and representative tool calls.

- [ ] **Step 1: Update the initialize fixture to record requests and suppress notification responses**

Make the fixture log every request, return a response whose ID matches the incoming request, return a realistic initialize result, and emit no line for `notifications/initialized`.

- [ ] **Step 2: Extend the initialize test assertions**

Assert the request sequence is `initialize`, `notifications/initialized`; assert initialize parameters contain the fixed protocol version, empty capabilities, and clientInfo; assert the notification has no `id`; assert only one response was observed.

- [ ] **Step 3: Update protocol-operation expectations**

For `mcp-tool-discovery`, expect `initialize`, `notifications/initialized`, `tools/list` with IDs `1` and `2` on requests. For `mcp-representative-readonly`, additionally expect `tools/call` with ID `3` and the existing tool arguments. Assert all initialize and discovery requests use the expected empty/object parameter shapes.

- [ ] **Step 4: Run the focused script and verify the new assertions fail before implementation**

Run:

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: the MCP probe tests fail because the current executor sends empty initialize parameters, omits the initialized notification, and sends tools/list first for standalone discovery.

### Task 2: Implement the MCP handshake and response accounting

**Files:**
- Modify: `skills/agent-driven-setup/scripts/run-target-probes.sh:378-496`

**Interfaces:**
- Consumes: Contract probe request mode and existing runtime subprocess.
- Produces: JSON-RPC messages with explicit response expectations and valid MCP lifecycle ordering.

- [ ] **Step 1: Add fixed initialize and notification message definitions**

Create initialize parameters with `protocolVersion: "2025-06-18"`, `capabilities: {}`, and `clientInfo` containing stable `name` and `version` strings. Add an `initialized` notification with JSON-RPC version and method but no ID.

- [ ] **Step 2: Build complete message sequences for all request modes**

Use ID `1` for initialize, ID `2` for tools/list, and ID `3` for tools/call. Build these sequences:

```text
initialize: initialize request, initialized notification
tool_discovery: initialize request, initialized notification, tools/list request
representative_tool_call: initialize request, initialized notification, tools/list request, tools/call request
```

- [ ] **Step 3: Change the send loop to wait only for response-bearing messages**

Write every message to stdin. For notification entries, flush and continue without reading stdout. For request entries, retain the current timeout, JSON parsing, response ID, result/error exclusivity, and error handling checks.

- [ ] **Step 4: Count only expected responses**

Derive `expected_count` from request entries rather than `len(messages)`. Keep evidence fields and runtime failure behavior unchanged.

### Task 3: Run regression and repository validation

**Files:**
- Verify: `skills/agent-driven-setup/scripts/run-target-probes.sh`
- Verify: `skills/agent-driven-setup/scripts/test-scripts.sh`
- Verify: `scripts/validate-skills.js`

**Interfaces:**
- Consumes: Updated executor and tests.
- Produces: Passing MCP-specific and repository-wide validation with no unintended diff.

- [ ] **Step 1: Run the full shell test suite**

Run `bash skills/agent-driven-setup/scripts/test-scripts.sh` and require zero failures.

- [ ] **Step 2: Run skill validation**

Run `node scripts/validate-skills.js` and require zero errors and warnings.

- [ ] **Step 3: Inspect the diff and shell syntax**

Run `bash -n skills/agent-driven-setup/scripts/run-target-probes.sh` and `git diff --check`. Confirm only the design, plan, probe executor, and test harness files changed.

### Task 4: Commit and push the verified change

**Files:**
- Commit: the design, plan, probe executor, and test harness changes after verification.

**Interfaces:**
- Consumes: Passing validation from Task 3.
- Produces: A pushed commit on the current branch.

- [ ] **Step 1: Review repository status, diff, and recent commits**

Run `git status`, `git diff`, and `git log --oneline -10`; do not stage unrelated `.worktrees/` content.

- [ ] **Step 2: Create a Japanese Conventional Commit**

Stage only the four intended files and commit with a concise message such as:

```bash
git add docs/superpowers/specs/2026-09-18-mcp-probe-handshake-design.md docs/superpowers/plans/2026-09-18-mcp-probe-handshake-plan.md skills/agent-driven-setup/scripts/run-target-probes.sh skills/agent-driven-setup/scripts/test-scripts.sh
git commit -m "fix: MCPプローブの初期化フローを修正"
```

- [ ] **Step 3: Push the current branch**

Run `git push` using the configured upstream. Do not merge a pull request.
