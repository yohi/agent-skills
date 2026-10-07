# Browser Debug Agent Skill — Full Requirements

This file contains the complete requirement catalog from issue #27. The
normative runtime instructions live in `SKILL.md`; this document provides the
full rationale, requirement IDs, and acceptance criteria.

## 1. Purpose

The AI agent must be able to remotely operate a real browser on an Ubuntu
Desktop host from an Ubuntu Server host, and without human intervention:

- verify behavior in a real browser
- reproduce defects
- observe DOM / Console / Network / Runtime state
- analyze root cause
- apply necessary source-code fixes
- re-verify after fixes
- perform regression checks
- report results and evidence

This skill does **not** implement browser control. It orchestrates existing
official browser MCPs.

## 2. System architecture

```text
Ubuntu Desktop / Browser Host
│
├─ Google Chrome / Chromium
│    ├─ headful browser
│    ├─ dedicated automation profile
│    └─ CDP endpoint :9222
│
└─ SSH reverse tunnel
         │
         ▼
Ubuntu Server / AI Agent Host
│
├─ AI Agent
├─ Chrome DevTools MCP
├─ Playwright MCP (optional)
└─ Browser Debug Skill
```

The agent treats the CDP endpoint exposed through the SSH tunnel as a local
endpoint, e.g. `http://127.0.0.1:9222`.

## 3. Basic policy

### R-BD-001 — Use official MCPs

The skill must not require a custom browser-control wrapper. Use the Chrome
DevTools MCP directly, and optionally the Playwright MCP. Custom MCPs or MCP
wrappers are not mandatory.

### R-BD-002 — Orchestration only

The skill's responsibility is to define:

```text
when
what
in what order
under what conditions
```

The skill must not reimplement:

```text
CDP client
browser driver
DOM parser
network inspector
screenshot engine
Playwright protocol
Chrome DevTools protocol
```

## 4. Target use cases

| ID | Use case | Example user prompt |
|---|---|---|
| UC-001 | Verification | この機能が実ブラウザで正常に動作することを確認して |
| UC-002 | Reproduction | 保存ボタンを押すと失敗するので再現して |
| UC-003 | Browser debugging | ブラウザでエラー原因を調査して |
| UC-004 | Post-fix verification | この変更がブラウザで直っているか確認して |
| UC-005 | Autonomous fix loop | Reproduce → Investigate → Root cause → Fix → Re-verify |

## 5. Skill activation conditions

### R-BD-010 — Explicit activation

Activate on prompts such as:

```text
ブラウザで確認して
実ブラウザで確認して
動作確認して
ブラウザでデバッグして
UIを確認して
E2Eで確認して
実際に操作して確認して
Consoleを確認して
Networkを確認して
```

### R-BD-011 — Implicit activation

Activate for Web UI problems that cannot be judged sufficiently by static
code review alone, such as:

```text
クリックしてもモーダルが開かない
ログイン後に画面が真っ白になる
APIは成功しているのに表示されない
```

### R-BD-012 — Avoid unnecessary activation

Do **not** activate for:

```text
純粋なバックエンド単体テスト
型エラーのみ
lintのみ
コンパイルエラーのみ
ブラウザ挙動と無関係なコードレビュー
```

## 6. Preconditions

### R-BD-020 — Browser endpoint

The CDP endpoint must be reachable, e.g. `127.0.0.1:9222`.

### R-BD-021 — Browser identity

Confirm the connected browser is the intended one. Capture at minimum:

```text
browser product
browser version
current page/session
```

### R-BD-022 — Dedicated browser profile

Never target a personal Chrome profile. Use a dedicated automation/debug
profile for:

```text
cookie isolation
credential isolation
localStorage isolation
history isolation
accident prevention
```

### R-BD-023 — Fail closed on connection failure

If the browser connection fails, do **not** report "ブラウザで確認済み".
Always terminate with an explicit state such as `NOT_VERIFIED`.

## 7. Standard debugging flow

```text
PRECHECK
   ↓
BASELINE
   ↓
REPRODUCE
   ↓
OBSERVE
   ↓
DIAGNOSE
   ↓
FIX
   ↓
VERIFY
   ↓
REGRESSION
   ↓
REPORT
```

For v1, `REGRESSION` is optional/future extension; the mandatory flow is:

```text
PRECHECK → REPRODUCE → OBSERVE → DIAGNOSE → [FIX if authorized] → VERIFY → REPORT
```

## 8. PRECHECK

### R-BD-030

Confirm first:

```text
browser endpoint reachable
target URL known
target app reachable
browser session available
required MCP tools available
```

### R-BD-031

If the target application cannot be reached, distinguish browser problems
from application-startup problems. Do not confuse:

```text
CDP unavailable
APP_UNREACHABLE
HTTP_ERROR
DNS_ERROR
TLS_ERROR
```

## 9. BASELINE

### R-BD-040

Record the state before interaction. Minimum:

```text
current URL
page title
DOM / accessibility snapshot
console baseline
network baseline
```

If useful, also record:

```text
screenshot
viewport
cookies/session existence
```

### R-BD-041

Distinguish existing Console errors from new errors caused by the current
operation.

## 10. REPRODUCE

### R-BD-050

If the user supplied reproduction steps, follow them. Do not replace them
with a different scenario.

### R-BD-051

Prefer semantic locators:

```text
role
label
text
accessible name
test id
```

Use unstable CSS selectors or coordinate clicks only as a last resort.

### R-BD-052

On successful reproduction, keep EXPECTED and ACTUAL separate.

### R-BD-053

If the defect cannot be reproduced, treat it as `NOT_REPRODUCED`. Do not
assume it is already fixed.

## 11. OBSERVE

After reproduction, observe in this order:

### R-BD-060 — Console

Check for:

```text
JavaScript exceptions
unhandled rejection
framework errors
warnings relevant to failure
CSP errors
CORS errors
```

### R-BD-061 — Network

Check for:

```text
failed requests
4xx
5xx
redirect loops
CORS
request payload
response status
relevant response body
WebSocket failure
```

### R-BD-062 — DOM

Check:

```text
expected element existence
visibility
disabled state
attributes
text
rendered state
form state
```

### R-BD-063 — Runtime

Investigate JavaScript runtime state as needed:

```text
window state
localStorage
sessionStorage
application-specific state
computed values
```

Keep arbitrary code execution read-only; do not accidentally mutate the
state under test.

### R-BD-064 — Screenshot

For visual problems, capture a screenshot as evidence:

```text
layout
modal
overflow
missing element
wrong style
blank screen
```

## 12. DIAGNOSE

### R-BD-070

Separate fact from hypothesis:

```text
FACT
HYPOTHESIS
```

### R-BD-071

Root-cause candidates must be supported by browser evidence or source-code
evidence.

### R-BD-072

Do not conclude cause from the first Console error alone. Confirm causality
against:

```text
user action
network event
runtime error
DOM change
source location
```

### R-BD-073

If the root cause cannot be identified, treat it as
`ROOT_CAUSE_NOT_PROVEN` and avoid expanding speculative changes.

## 13. FIX

### R-BD-080

Proceed to FIX only when code modification is explicitly authorized. Do not
change source code for review-only or investigation-only requests.

### R-BD-081

Prefer the minimal change that addresses the root cause.

### R-BD-082

Fix the root cause rather than a browser-only workaround when possible.

## 14. VERIFY

### R-BD-090

After a fix, reload the browser or restore the required initial state, then
re-run the same reproduction steps.

### R-BD-091

Do not judge success by UI alone. Confirm at minimum:

```text
expected UI/result
no relevant new Console error
no relevant failed Network request
expected DOM/application state
```

### R-BD-092

Only when the previously failing scenario succeeds under identical
conditions, label it `FIX_VERIFIED`.

## 15. REGRESSION

### R-BD-100

When regression checks are performed, confirm adjacent major operations such
as:

```text
create
edit
save
cancel
reload
navigation
```

### R-BD-101

If existing automated tests are available, run them alongside browser
verification when practical. However, `unit test passed` must **not** replace
`browser verified`.

## 16. Evidence requirements

### R-BD-110

Final judgments must be based on observable evidence. Candidate evidence:

```text
browser URL
DOM snapshot
screenshot
Console entry
Network request/result
runtime value
browser version
executed interaction
test result
```

### R-BD-111

Reports containing only "確認した" or "問題ない" are prohibited.

### R-BD-112

The final report must include at minimum:

```text
Result
Reproduction
Root cause
Fix
Browser verification
Regression
Remaining risks
```

## 17. Terminal states

Support at minimum:

```text
VERIFIED
FIX_VERIFIED
FAILED
NOT_REPRODUCED
NOT_VERIFIED
BLOCKED
ROOT_CAUSE_NOT_PROVEN
```

## 18. Tool selection policy

### Chrome DevTools MCP

Primary uses:

```text
Console
Network
DOM inspection
runtime inspection
performance investigation
browser debugging
```

### Playwright MCP

Use when needed for:

```text
navigation
click
fill
keyboard interaction
multi-step scenario
repeatable user flow
element-oriented operation
```

### R-BD-120

Do not redundantly run the same operation through both MCPs. Treat them as:

```text
Playwright = interaction
DevTools   = diagnosis
```

If one MCP is sufficient, use only that one.

## 19. Browser state management

### R-BD-130

Make the test state as reproducible as possible.

### R-BD-131

When prior state could affect results, explicitly record and report:

```text
cookies
localStorage
IndexedDB
service worker
cache
authentication
current URL
open tabs
```

### R-BD-132

The skill must not unconditionally wipe the browser profile. Profile reset
must be an explicit request or delegated to a separate management mechanism.

## 20. Security requirements

### R-BD-140

Do not expose the CDP port to the internet.

### R-BD-141

Reach the CDP endpoint only via `127.0.0.1` plus an SSH tunnel when possible.

### R-BD-142

Do not hand personal browser sessions, personal cookies, or password managers
to the AI.

### R-BD-143

When an authenticated browser is required, prefer test/development-only
accounts.

### R-BD-144

Do not unnecessarily output secrets to Console, reports, or artifacts. This
includes:

```text
Authorization header
cookie
token
password
API key
session secret
```

## 21. Fail-closed requirements

The following must **never** be treated as success:

```text
browser connection failure
cannot open target URL
reproduction steps incomplete
MCP tool failure
observation impossible
page crash
authentication failure
verification aborted mid-way
```

## 22. Timeout and retry

### R-BD-150

Infinite retry is prohibited.

### R-BD-151

Limited retry is allowed for transient browser states such as:

```text
page load
temporary network error
element rendering delay
```

### R-BD-152

If the same cause fails more than a fixed number of times, report `BLOCKED`
with the cause and the latest evidence.

## 23. Non-goals

The skill does **not** require:

```text
Chrome process start/stop
Chrome version management
Chrome installation
SSH tunnel setup
SSH tunnel recovery
profile creation
profile deletion
OS GUI automation
desktop window manager operations
VNC operations
```

These belong to the Browser Host infrastructure.

## 24. Future extension

If needed, add a separate Browser Host MCP / Plugin with APIs such as:

```text
browser_host_status
browser_host_start
browser_host_restart
browser_host_reset_profile
browser_host_create_profile
browser_host_collect_artifacts
```

This is separate from the Browser Debug Skill.

## 25. Acceptance criteria

Skill v1 is READY when all of the following are met:

| ID | Criterion |
|---|---|
| AC-001 | AI agent can connect to real Chrome on its own. |
| AC-002 | Agent can open a specified URL. |
| AC-003 | Agent can operate buttons, forms, etc. |
| AC-004 | Agent can capture Console errors. |
| AC-005 | Agent can capture Network failures. |
| AC-006 | Agent can check DOM state. |
| AC-007 | Agent can capture screenshot or equivalent visual evidence. |
| AC-008 | Agent can reproduce an intentionally prepared UI defect. |
| AC-009 | Agent can identify a defect root-cause candidate from browser evidence. |
| AC-010 | When authorized, agent can re-run the same browser scenario after a fix. |
| AC-011 | Agent can show pre-fix FAIL → post-fix PASS with evidence. |
| AC-012 | Agent does not return VERIFIED when the browser cannot be reached. |
| AC-013 | Agent does not use a normal personal Chrome profile. |
| AC-014 | Agent does not expose the CDP endpoint to an external network. |

## 26. v1 recommended scope

The first implementation targets:

```text
Chrome DevTools MCP
+ optional Playwright MCP
+ Browser Debug Skill
```

v1 flow:

```text
precheck
→ reproduce
→ console/network/DOM observation
→ diagnose
→ optional fix
→ verify
→ report
```

Excluded from v1:

```text
custom MCP
MCP wrapper
Browser Host Plugin
Chrome lifecycle control
profile lifecycle control
multi-browser support
Firefox
Safari/WebKit
mobile device farm
```

## 27. Final architectural principle

```text
MCP                    = capability / mechanism
Skill                  = workflow / policy / decision logic
Browser Host infrastructure = browser lifecycle / connectivity
```

These three responsibilities must not be mixed.
