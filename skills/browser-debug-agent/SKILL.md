---
name: browser-debug-agent
description: Guides an AI agent through real-browser debugging of web applications using Chrome DevTools MCP and optional Playwright MCP. Use whenever the user asks to verify behavior in a real browser, reproduce a UI bug, debug browser errors, check Console or Network, or confirm a fix in the browser. Also use for implicit browser-related issues such as 'modal does not open on click', 'blank screen after login', or 'API succeeds but nothing is displayed'. Do not use for pure backend unit tests, type-only errors, lint-only issues, compile-only errors, or code reviews unrelated to browser behavior.
---

# Browser Debug Agent

Debug and verify web applications in a real browser by orchestrating official
browser MCPs. This skill does **not** implement browser control itself; it
defines **when**, **what**, and **in what order** to call the Chrome DevTools
MCP and, when useful, the Playwright MCP.

This skill must remain **fail-closed**: a missing browser, unreachable
application, or incomplete observation must never be reported as success.

## When to use this skill

Use this skill when the user asks for:

- Real-browser verification: "ブラウザで確認して", "実ブラウザで確認して",
  "動作確認して", "UIを確認して", "E2Eで確認して", "実際に操作して確認して"
- Browser diagnosis: "ブラウザでデバッグして", "Consoleを確認して",
  "Networkを確認して"
- Bug reproduction involving the UI
- Post-fix browser verification: "この変更がブラウザで直っているか確認して"

Also use it for implicit browser-related problems where static review is not
enough:

- "クリックしてもモーダルが開かない"
- "ログイン後に画面が真っ白になる"
- "APIは成功しているのに表示されない"

## When not to use this skill

Do **not** use this skill for:

- Pure backend unit tests
- Type errors only
- Lint-only issues
- Compile-only errors
- Code reviews unrelated to browser behavior

## Required tools

The skill expects at least one of these MCPs to be available:

- **Chrome DevTools MCP** — primary tool for Console, Network, DOM inspection,
  runtime inspection, screenshots, and performance investigation.
- **Playwright MCP** (optional) — for multi-step interaction such as navigation,
  click, fill, keyboard input, and repeatable user flows.

Do not reimplement CDP, browser drivers, DOM parsers, network inspectors,
screenshot engines, or Playwright protocol logic. Rely on the MCPs.

## Standard v1 workflow

Run the following phases in order. Skip `FIX` unless the user explicitly
authorized code modification. Skip `REGRESSION` in v1; it is reserved as a
future extension.

```text
PRECHECK
  → BASELINE
  → REPRODUCE
  → OBSERVE
  → DIAGNOSE
  → [FIX, only if authorized]
  → VERIFY
  → REPORT
```

Maintain an evidence ledger throughout. Every factual claim in the final
report must reference a concrete observation such as a URL, DOM snapshot,
screenshot, Console entry, Network request/response, runtime value, browser
version, executed interaction, or test result.

## 1. PRECHECK

Before any browser operation, confirm:

1. **Browser endpoint reachable** — e.g. `http://127.0.0.1:9222`.
2. **Target URL known** — the application URL to test.
3. **Target app reachable** — distinguish browser problems from app startup
   problems (`CDP unavailable`, `APP_UNREACHABLE`, `HTTP_ERROR`, `DNS_ERROR`,
   `TLS_ERROR`).
4. **Browser session available** — a dedicated automation/debug profile is
   being used, never a personal Chrome profile.
5. **Required MCP tools available** — at least Chrome DevTools MCP is
   accessible.

If any check fails, stop and report the exact state:

```text
NOT_VERIFIED
```

or, when blocked by repeated failures:

```text
BLOCKED
```

Never report "verified" or "looks fine" when the browser cannot be reached.

## 2. BASELINE

Record the state before interacting with the page:

- current URL
- page title
- DOM / accessibility snapshot
- console baseline
- network baseline

If useful, also record:

- screenshot
- viewport
- cookies / session existence

After the reproduction step, distinguish **pre-existing** Console errors and
Network failures from **new** ones caused by the tested action.

## 3. REPRODUCE

Follow the user's reproduction steps exactly. Do not replace them with a
different scenario.

Prefer **semantic locators** over brittle selectors:

- role
- label
- visible text
- accessible name
- `data-testid`

Use CSS selectors or coordinate clicks only as a last resort.

Capture:

- **EXPECTED** — what should happen
- **ACTUAL** — what actually happened

If the issue cannot be reproduced, report:

```text
NOT_REPRODUCED
```

Do **not** guess that the bug is already fixed.

## 4. OBSERVE

After reproduction, observe in this order:

1. **Console** — JavaScript exceptions, unhandled rejections, framework errors,
   relevant warnings, CSP errors, CORS errors.
2. **Network** — failed requests, 4xx, 5xx, redirect loops, CORS issues,
   request payloads, response statuses, relevant response bodies, WebSocket
   failures.
3. **DOM** — expected element existence, visibility, disabled state,
   attributes, text, rendered state, form state.
4. **Runtime** — `window` state, `localStorage`, `sessionStorage`,
   application-specific state, computed values. Prefer read-only inspection.
5. **Screenshot** — for visual problems such as layout issues, missing modals,
   overflow, wrong style, or blank screens.

If observations cannot be collected because the browser is unreachable or the
reproduction step could not run, still record the observation ledger. Do not
omit it just because PRECHECK failed. Use statuses such as:

```text
Console:    NOT_COLLECTED
Network:    NOT_COLLECTED
DOM:        NOT_COLLECTED
Runtime:    NOT_COLLECTED
Screenshot: NOT_COLLECTED
```

The fact that each category was attempted but unavailable is itself evidence.

## 5. DIAGNOSE

Separate observations from interpretation:

- **FACT** — something actually observed
- **HYPOTHESIS** — a possible explanation

Root-cause candidates must be backed by browser evidence or source-code
evidence. Do not conclude causality from the first Console error alone.
Confirm the relationship between the user action, network event, runtime
error, DOM change, and source location.

If the root cause cannot be proven, report:

```text
ROOT_CAUSE_NOT_PROVEN
```

and avoid speculative, broad changes.

## 6. FIX

Enter this phase **only** if the user authorized code modification. Maintain
three independent state flags:

```text
fix_authorized — did the user authorize code modification?
fix_applied    — was source code actually changed?
fix_verified   — was the fix confirmed in a real browser under identical conditions?
```

These are separate concepts. `fix_authorized = true` with `fix_applied = false`
and `fix_verified = false` is a valid state when the browser is unreachable or
the root cause is unproven.

### FIX authorization

FIX authorization is granted by explicit user intent to modify the
implementation. Treat the following as authorized:

```text
修正して
直して
原因を調査して修正して
fix this bug
implement the fix
make the necessary code changes
```

Do **not** treat the following as authorized:

```text
調査して
原因を教えて
デバッグして
レビューして
コード変更はしないで
investigate only
just tell me what's wrong
```

### When fixing

- Prefer the smallest change that addresses the root cause.
- Fix the root cause rather than hiding the symptom in the browser.
- Do not change code when the root cause is unproven.
- If the browser is unavailable but the user explicitly authorized a source-code
  fallback (e.g. "ブラウザが使えなければソースコードを見て直して"), you may
  apply a provisional source fix. You must still report that the fix is
  **unverified** until browser verification is performed.

## 7. VERIFY

After any fix:

1. Reload the browser or return to the required initial state.
2. Re-run the **same** reproduction steps.
3. Confirm all of the following:
   - expected UI / result
   - no relevant new Console error
   - no relevant failed Network request
   - expected DOM / application state

Only when the previously failing scenario now succeeds under identical
conditions, report:

```text
FIX_VERIFIED
```

Never report `FIX_VERIFIED` without actually running the scenario again.

If a fix was applied but the browser cannot be reached for verification, report:

```text
FIX_APPLIED_NOT_VERIFIED
```

or keep the result as `NOT_VERIFIED` / `ROOT_CAUSE_NOT_PROVEN` with a clear
note that the fix has not been browser-verified.

## 8. REPORT

Final reports must be evidence-based. Reports containing only "確認した" or
"問題ない" are not allowed.

Include at minimum:

- **Result** — one of `VERIFIED`, `FIX_VERIFIED`, `FIX_APPLIED_NOT_VERIFIED`,
  `FAILED`, `NOT_REPRODUCED`, `NOT_VERIFIED`, `BLOCKED`, `ROOT_CAUSE_NOT_PROVEN`
- **Reproduction** — steps taken and observed ACTUAL vs EXPECTED
- **Root cause** — or `ROOT_CAUSE_NOT_PROVEN` if not proven
- **Fix** — if performed
- **Browser verification** — evidence from VERIFY
- **Regression** — only if explicitly requested and run; otherwise note it was
  skipped per v1 scope
- **Remaining risks** — unverified states, assumptions, or follow-up items

Redact secrets before including any evidence. Do not output Authorization
headers, cookies, tokens, passwords, API keys, or session secrets.

## Tool selection

Use each MCP for what it is good at:

- **Playwright MCP** = interaction (navigation, click, fill, keyboard,
  repeatable user flows, element-oriented operations).
- **Chrome DevTools MCP** = diagnosis (Console, Network, DOM inspection,
  runtime inspection, performance investigation, screenshots).

Avoid running the same operation through both MCPs without reason. If one MCP
is sufficient, use only that one.

## Security and safety

- Use a dedicated automation/debug browser profile. Never use a personal
  Chrome profile or personal credentials.
- Reach the CDP endpoint only via `127.0.0.1` and an SSH tunnel when possible.
  Do not expose the CDP port to the internet.
- Prefer test/development accounts for authenticated flows.
- Redact secrets from Console logs, reports, and any saved artifacts.
- Do not unconditionally wipe browser profiles. Profile reset must be an
  explicit request or handled by a separate browser-host mechanism.

## Fail-closed checklist

Treat the following as failure, never as success:

- browser connection failure
- target URL cannot be opened
- reproduction steps incomplete
- MCP tool failure
- observation impossible
- page crash
- authentication failure
- verification aborted mid-way

## Browser state awareness

When prior browser state could affect results, explicitly record and report:

- cookies
- localStorage
- IndexedDB
- service worker
- cache
- authentication
- current URL
- open tabs

## Non-goals (out of scope)

This skill does **not** manage:

- Chrome process start/stop
- Chrome version management
- Chrome installation
- SSH tunnel setup or recovery
- browser profile creation or deletion
- OS GUI automation
- desktop window manager operations
- VNC operations

Those are responsibilities of the Browser Host infrastructure, not this skill.

## Reference

For the complete requirement catalog including all `R-BD-xxx` definitions,
acceptance criteria, and future extensions, read
[references/requirements.md](references/requirements.md).
