# Integration Report — Scenario B: post-login-blank

## Run metadata

- Baseline: `d75d376d17c8558b90f18f1d037fd548455853b3`
- Scenario branch: `scenario-b-post-login-blank`
- Target flow: `http://127.0.0.1:3000/login.html` → `http://127.0.0.1:3000/dashboard.html`
- Browser: Google Chrome 155 (`navigator.userAgent`: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36`)
- Browser MCP: `chrome-devtools-mcp@1.10.1`
- Result: `FIX_VERIFIED`

> This report preserves paths as they were recorded during Scenario B. The
> current evaluation workspace is `evals/browser-debug-agent/`.

## Branch isolation and PRECHECK

- The Scenario B branch was created directly from `d75d376d17c8558b90f18f1d037fd548455853b3` after the Scenario A branch was committed and clean.
- Scenario A's commit `5d69e89083c05ff1560e095b16090a56d200d5fe` is not an ancestor of this branch; Scenario A's server fix, test, report, and screenshot are absent from the B branch.
- `npm run fixture:post-login-blank` completed and printed `{ settingsSaveFails: true, dashboardThrows: true }`.
- Chrome runtime inspection of `/api/config` returned `{"settingsSaveFails":true,"dashboardThrows":true}` before and after the fix. The dashboard bug flag remained true for verification.
- The app was restarted after switching to the baseline branch, then restarted after the frontend source fix.

## REPRODUCE — before fix

The Login page loaded at `/login.html`, title `Login`. The form showed the test username and a masked password. The pre-action Console contained only an autocomplete issue/warning. The login page request returned 200; the app script returned 304.

Clicking Login in Chrome DevTools MCP navigated to `/dashboard.html`.

| Evidence | Observed |
|---|---|
| Network | `POST /api/login` returned 200; `GET /dashboard.html` returned 200; dashboard `GET /api/config` returned 304 with cached JSON `{"settingsSaveFails":true,"dashboardThrows":true}`. |
| Console | `Uncaught (in promise)`; stack: `renderDashboard (app.js:49:11)`, called by the inline script in `dashboard.html`. |
| DOM/runtime | Dashboard heading existed, `#dashboard-content` existed but was empty, and body text was only `Dashboard`. |
| Screenshot | `evidence/scenario-b-after.png` captures the blank dashboard. `evidence/scenario-b-before.png` captures the Login page before the action. |

**EXPECTED:** Login succeeds and the dashboard content renders.

**ACTUAL:** Login succeeded and navigation completed, then dashboard rendering threw and left the content area blank.

## DIAGNOSE

**FACT:** The browser reached the dashboard after a successful `/api/login` response. The Console stack identified `renderDashboard` at `app.js:49:11`; runtime inspection showed the dashboard container empty. The baseline `public/app.js` branch for `dashboardThrows` cleared the container and threw `Dashboard render failed: authState is undefined`.

**Root cause:** The frontend intentionally cleared the dashboard content and threw when the `dashboardThrows` fixture was true. Login and navigation were not the failing parts of the flow.

## FIX

`browser-debug-agent-workspace/integration/buggy-app/public/app.js` no longer clears the dashboard and throws based on `dashboardThrows`; it proceeds to render the dashboard content. The fixture remained true.

A regression test was added at `browser-debug-agent-workspace/integration/buggy-app/test/dashboard-render.test.js`. It evaluates the real renderer with the fixture response enabled and asserts that dashboard content is rendered.

### Git diff summary

```diff
-  if (config.dashboardThrows) {
-    container.textContent = '';
-    throw new Error('Dashboard render failed: authState is undefined');
-  }
-
   container.innerHTML = `
```

## TEST

- RED before the fix: `node --test test/dashboard-render.test.js` failed with `Dashboard render failed: authState is undefined` when the fixture response had `dashboardThrows=true`.
- GREEN after the fix: `node --test` reported **1 pass, 0 failures**.

## VERIFY — same real-browser flow after fix

With the fixture still reporting `dashboardThrows=true`, the same Chrome tab was opened at `/login.html` and the same Login action was performed.

| Evidence | Observed |
|---|---|
| Network | `POST /api/login` returned 200; `GET /dashboard.html` returned 304 from cache; `GET /app.js` returned 304 and its response body contained the updated renderer; `GET /api/config` returned 304 with cached JSON confirming `dashboardThrows=true`. |
| Console | No messages after the successful flow. |
| DOM | Dashboard heading, `Welcome, user!`, and `Dashboard loaded successfully.` were present. |
| Runtime | URL was `http://127.0.0.1:3000/dashboard.html`; `#dashboard-content` contained the rendered paragraphs. |
| Screenshot | `evidence/scenario-b-fixed.png` captures the rendered dashboard. |

The same Login-to-Dashboard browser flow now succeeds while the bug fixture remains enabled, so the result is `FIX_VERIFIED`.
