# Web checks (X Coder + Dev Tools, 3.11.0)

Headless-Chromium checks for the JavaScript that runs inside WebViews:

| Script | Checks |
|---|---|
| `editor_check.js` | `assets/xcoder/editor.html` + bundled Ace: open/switch/close files, themes, linting workers, autocomplete popup, format (JSON/HTML/CSS), find/replace, outline, comment, move lines, undo. |
| `runner_check.js` | The JavaScript runner harness in `lib/features/xcoder/run/js_runner.dart` (console, tables, timers, async, errors, `require`, `process.exit`). |
| `devtools_check.js` | `kDevtoolsHook` (console/network capture) and `assets/devtools/nxdt_agent.js` (DOM tree, shadow DOM, styles, storage, sources, perf, audit, security headers, clear site data). |
| `console_eval_check.js` | The Dev Tools console evaluator in `devtools_bridge.dart` (expressions, statements, top-level await, runtime vs. parse errors). |

```bash
npm i playwright@1 && npx playwright install chromium   # once
node tools/web_checks/editor_check.js
node tools/web_checks/runner_check.js
node tools/web_checks/devtools_check.js
node tools/web_checks/console_eval_check.js
```
Each script prints `PASS`/`FAIL` lines and exits non-zero on failure.
