# Agent Setup Script Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct install-document discovery, command safety classification, and Makefile target discovery without changing the helper scripts' public JSON schema.

**Architecture:** Keep the existing Bash and embedded-Python structure. Make the smallest changes at each faulty boundary: append an actual newline for list encoding, use an allowlist for direct execution, and tokenize only valid Make rule left-hand sides. Extend the existing shell test harness with fixtures that exercise each regression.

**Tech Stack:** Bash, embedded Python 3, `python3 -c` assertions.

## Global Constraints

- Do not modify the scripts' command-line interfaces or emitted JSON keys.
- Do not execute repository-defined commands while producing a verification plan.
- Do not stage pre-existing untracked files.
- Do not use subagents.

---

### Task 1: Cover and Correct Install Document Encoding

**Files:**
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh:30-56`
- Modify: `skills/agent-driven-setup/scripts/analyze-repo.sh:171-176`

**Interfaces:**
- Consumes: `analyze-repo.sh` JSON field `install_docs`.
- Produces: A JSON array containing one string for each discovered install document.

- [ ] **Step 1: Write the failing regression assertion**

In `check_analysis`, create `docs/install.md` and `INSTALL.md`, then add this assertion to the embedded Python check:

```python
assert data["install_docs"] == ["docs/install.md", "INSTALL.md"]
```

- [ ] **Step 2: Run the harness to verify the assertion fails**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: the analysis test fails because the current output contains a single string with literal `\\n` separators.

- [ ] **Step 3: Append an actual newline**

Replace the accumulation expression with:

```bash
install_docs+="$candidate"$'\n'
```

This preserves the existing `encode_list` contract, which converts actual newline delimiters to `|` before JSON parsing.

- [ ] **Step 4: Run the harness to verify the regression passes**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: all tests pass, including the new two-document assertion.

### Task 2: Make Command Classification Allowlist-Based

**Files:**
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh:58-84`
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh:65-74`

**Interfaces:**
- Consumes: command strings in `analyze.json`.
- Produces: `safe` only for `safe_prefixes`; `review` for unmatched or risk-keyword commands.

- [ ] **Step 1: Write failing safe and unknown command assertions**

Use this fixture JSON in `check_verification_plan`:

```json
{
  "test_command": "npm test",
  "build_command": "unknown-command --check",
  "env_template": false
}
```

Add assertions that the unknown build command is `review` and the test command
is `safe`. Commands are collected in build-then-test order:

```python
assert plan["commands"][0]["category"] == "review"
assert plan["commands"][1]["category"] == "safe"
```

- [ ] **Step 2: Run the harness to verify the unknown-command assertion fails**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: the verification-plan test fails because the unknown command is currently marked `safe`.

- [ ] **Step 3: Default to review and explicitly allow safe prefixes**

Set the initial category to `"review"`. Check `safe_prefixes` before scanning
`review_keywords`, then let a matching review keyword overwrite the category:

```python
category = "review"
for prefix in safe_prefixes:
    if lower.startswith(prefix):
        category = "safe"
        break
for kw in review_keywords:
    if kw in lower:
        category = "review"
        break
```

- [ ] **Step 4: Run the harness to verify the revised classification passes**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: `npm test` is safe and an unknown command requires review.

### Task 3: Parse Makefile Targets Conservatively

**Files:**
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh:68-83`
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh:109-120`

**Interfaces:**
- Consumes: root `Makefile` lines.
- Produces: `makefile_targets` as an array of individual, non-dot-prefixed rule targets.

- [ ] **Step 1: Write failing Makefile fixture and assertion**

Add variable assignments and a multi-target rule to the fixture:

```make
VERSION := 1
OPTION ?= default
test lint:

```

Assert the output contains only the split rule targets:

```python
assert plan["makefile_targets"] == ["test", "lint"]
```

- [ ] **Step 2: Run the harness to verify the target assertion fails**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: the output contains `VERSION` and/or a combined `test lint` item.

- [ ] **Step 3: Exclude assignments and split the rule left-hand side**

Import `re` and skip Make variable assignment lines before target collection:

```python
if re.match(r"^[A-Za-z_][A-Za-z0-9_.-]*\s*(?::=|\?=|\+=|!=)", line):
    continue
```

For a remaining rule line, split its left-hand side on whitespace and append each
non-dot-prefixed target separately:

```python
for target in line.split(":", 1)[0].split():
    if target and not target.startswith("."):
        targets.append(target)
```

- [ ] **Step 4: Run the harness to verify target discovery passes**

Run: `bash skills/agent-driven-setup/scripts/test-scripts.sh`

Expected: assignments are absent and `test` and `lint` are separate values.

### Task 4: Validate and Publish the Fix

**Files:**
- Modify: `skills/agent-driven-setup/scripts/analyze-repo.sh`
- Modify: `skills/agent-driven-setup/scripts/verify-setup.sh`
- Modify: `skills/agent-driven-setup/scripts/test-scripts.sh`

**Interfaces:**
- Consumes: the completed script and test changes.
- Produces: a verified commit containing only intended files, pushed to its tracking remote.

- [ ] **Step 1: Run complete focused validation**

Run:

```bash
bash skills/agent-driven-setup/scripts/test-scripts.sh
bash -n skills/agent-driven-setup/scripts/analyze-repo.sh
bash -n skills/agent-driven-setup/scripts/verify-setup.sh
node scripts/validate-skills.js
```

Expected: every command exits with status 0.

- [ ] **Step 2: Inspect the final patch and staging scope**

Run:

```bash
git status --short
git diff --check
git diff -- skills/agent-driven-setup/scripts/analyze-repo.sh skills/agent-driven-setup/scripts/verify-setup.sh skills/agent-driven-setup/scripts/test-scripts.sh
```

Expected: only the three intended scripts and this plan are selected for the implementation commit; existing untracked files remain unstaged.

- [ ] **Step 3: Commit and push only intended files**

Run:

```bash
git add skills/agent-driven-setup/scripts/analyze-repo.sh skills/agent-driven-setup/scripts/verify-setup.sh skills/agent-driven-setup/scripts/test-scripts.sh docs/superpowers/plans/2026-09-07-agent-setup-script-hardening.md
git commit -m "fix: セットアップ検証補助の判定を安全化"
git push
```

Expected: the remote tracking branch receives the commit without staging any pre-existing untracked files.
