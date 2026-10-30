// lib/features/devguide/guide_content.dart
//
// Content of the NOVA X Developer Guide (Markdown, rendered by
// NovaMarkdownView). Keep it in sync with the features it describes.

import 'package:flutter/material.dart';

class GuideSection {
  const GuideSection({
    required this.id,
    required this.tab,
    required this.title,
    required this.icon,
    required this.color,
    required this.body,
    this.subtitle = '',
  });
  final String id;
  final String tab;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String body;
}

const List<GuideSection> kGuideSections = [
  GuideSection(
    id: 'start',
    tab: 'Start here',
    title: 'Start here',
    subtitle: 'The developer toolbox in NOVA X',
    icon: Icons.rocket_launch_outlined,
    color: Color(0xFF00D4FF),
    body: r'''
| Tool | What it's for | Where |
|---|---|---|
| **X Coder** | Code editor with projects, terminal, live preview | Home › X Coder |
| **NOVA Coder** | AI pair programmer (fix, explain, refactor, tests…) | X Coder › ✨ |
| **NOVA Agent** | Describe a change; it edits several files for you | X Coder › 🤖 |
| **Dev Tools** | Inspect any website: elements, console, network… | Browser › ⋮ › Developer tools |
| **NOVA Cyber** | Security scan of a website (OWASP Top 10) | Browser › ⋮ › NOVA Cyber |
| **NOVA Shield** | Encrypted DNS, HTTPS-only, anti-tracking | Home › NOVA Shield |
| **NOVA Network** | Speed, latency, bufferbloat, device details | Home › NOVA Network |
| **NOVA Capture** | Screenshots & screen recordings of your work | Home › NOVA Capture |

**A typical flow:** build a page in **X Coder** → ▶ **Run** to preview it → open it in the browser and use **Dev Tools** to debug → scan the live site with **NOVA Cyber** → record a demo with **NOVA Capture**.

> Most tools work **offline**: the editor, linting, terminal, preview, Dev Tools on cached pages and this guide. NOVA Coder, NOVA Cyber and speed tests need internet.
''',
  ),
  GuideSection(
    id: 'xcoder',
    tab: 'X Coder',
    title: 'X Coder',
    subtitle: 'A VS Code-style editor on your phone',
    icon: Icons.code_rounded,
    color: Color(0xFF42A5F5),
    body: r'''
### Projects
- Every project is a real folder on your phone. Open **☰ › project name** to switch, create (*Website, JavaScript, Python, PHP, Notes, Empty* templates), rename, export as **.zip** or delete.
- **Free:** 2 projects · **Premium:** unlimited projects + NOVA Coder & Agent.
- Changes are **saved automatically** a moment after you stop typing (Settings › Auto save). Unsaved tabs show a **●**.

### Explorer (☰)
- Tap a file to open it, tap a folder to expand it.
- **Long-press** any file or folder: *Open, Run, New file, New folder, Import files here, Rename, Duplicate, Copy path, Delete*.
- **Filter files** box at the top; red numbers = errors in that file.
- **Open editors** lists your tabs (close them with ✕).

### Editor
- Highlighting for 45+ languages, 15 themes (⋮ › Settings).
- **Suggestions while you type**: keywords, snippets, words from the file and the whole project. Tap a suggestion or press Tab/Enter.
- **Live error checking** for JavaScript, CSS, HTML, JSON, PHP, XML and YAML — red/yellow marks in the gutter, and the list in **PROBLEMS**.
- Auto-closing brackets and quotes, code folding (arrows in the gutter), indent guides.
- **Multi-cursor:** select a word, then *Add next occurrence* (keys row or Ctrl+D).
- **Format document** for HTML, CSS, JS/TS, JSON, PHP, XML (⋮ › Format, or Shift+Alt+F). Turn on *Format on save* in Settings.

### Extra keys row
Shown above the keyboard: **⇥ Tab · ⇤ outdent · ← ↑ ↓ → · { } ( ) [ ] < > ; : = " ' ` / \ | & ! $ # % * + - _ @ ~ ^ ,** · Undo · Redo · 💡 Suggestions · 🔍 Find · Comment · Duplicate line · Multi-cursor · ✨ NOVA · Hide keyboard.

### Command palette
Tap the search bar at the top (or Ctrl+P / Ctrl+Shift+P):
- type a **file name** → open it (fuzzy: `btncss` finds `styles/button.css`)
- `>` → **commands** (save, format, fold, sort lines, change language, export…)
- `:42` → **go to line** 42
- `@` → **go to a function/class** in this file

### Bottom panel
**PROBLEMS** (errors, tap to jump, *Fix with NOVA*) · **TERMINAL** · **OUTPUT** (results of ▶ Run and the preview console) · **SEARCH** (find & replace across the whole project; regex `.*`, case `Aa`, whole word `ab`, include filter like `*.js, src/`).

### ▶ Run
| File | What ▶ does |
|---|---|
| `.html` | Live preview on `localhost` with a console, phone/tablet/desktop widths, auto-reload on save, "Open in NOVA X browser" for Dev Tools |
| `.js` | Runs in the phone's V8 engine; output in OUTPUT |
| `.md` | Shows the rendered Markdown |
| `.json` | Validates it and shows the error position |
| `.css` | Previews the project's HTML page |
| `.sh` | Runs it in the terminal |
| `.php`, `.py`, others | Can't run on a phone — use NOVA to explain/test, run on a server |

### Import & export
⋮ › **Import files** (from the phone), **Download from URL**, **Export project (.zip)**. Images open in a viewer; binary files can't be edited; files over 2 MB open read-only.
''',
  ),
  GuideSection(
    id: 'novacoder',
    tab: 'NOVA Coder',
    title: 'NOVA Coder & NOVA Agent',
    subtitle: 'AI pair programmer · Premium',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFFFFD54F),
    body: r'''
NOVA Coder is the AI engine of X Coder. It sees your **open file, your selection, other open tabs, the project's file list, the errors in PROBLEMS and recent terminal/console output** — so you rarely need to explain the context.

### NOVA Coder (✨)
Pick a task and tap **Send** (answers stream in live):

| Task | Use it to… |
|---|---|
| **Ask** | Ask anything about your code; follow-up questions keep the conversation |
| **Generate** | Write new code from a description → *Insert at cursor* or *New file* |
| **Complete** | Continue the code at the cursor |
| **Explain** | Understand unfamiliar code |
| **Fix** | Fix bugs using the editor's diagnostics → review the **diff** → *Apply* |
| **Debug** | Find the root cause of an error, step by step |
| **Refactor / Optimize / Comment** | Cleaner, faster, documented code (diff first) |
| **Tests** | Unit tests → *New file* with a suggested name |
| **Review** | Senior-engineer review: Critical / Major / Minor |
| **Security** | Audit for injection, XSS, secrets, auth problems |
| **Docs** | README-style docs → *Save as README* |

**Scope:** with code selected, NOVA works on the **selection** (tap the chip to switch to the whole file).

### NOVA Agent (🤖)
Describe a change in plain words — *"add a dark-mode toggle that remembers the choice"*. The agent:
1. reads the project tree and **asks for the files it needs** (you'll see "Reading src/app.js…"),
2. returns a **plan**: summary, steps, **file edits**, suggested **commands**,
3. you tap each file to see its **diff**, untick anything you don't want, then **Apply**.
Commands run only when you tap **Run**. If the agent asks a question, just answer in the box.

### AI completion
**⋮ › Command palette › NOVA: Complete code at the cursor** (or **Alt+\**) inserts a suggestion at the cursor — Undo removes it.

### From the terminal
`nova why does my fetch fail?` · `agent split app.js into modules`

### Good to know
- Nothing changes in your files until you tap **Apply / Insert**. **Undo** reverts applied edits in open files.
- NOVA never runs commands or code by itself.
- Requests per day are limited (fair use); the usage resets at midnight UTC.
- Your code is sent to the NOVA Coder service only when you use it, and isn't stored.
''',
  ),
  GuideSection(
    id: 'terminal',
    tab: 'Terminal',
    title: 'Terminal',
    subtitle: 'Every command, with examples',
    icon: Icons.terminal_rounded,
    color: Color(0xFF4EAA25),
    body: r'''
Open it with **TERMINAL** in the bottom panel (or Ctrl+backtick). It runs **inside the project folder** with Android's built-in shell tools. Keys: **↑** history · **Tab** complete file names · **^C** stop · **⏎** run. While a program runs, what you type is sent to it (stdin).

### X Coder commands
| Command | What it does | Example |
|---|---|---|
| `help` | List commands | `help` |
| `clear` / `cls` | Clear the screen (also Ctrl+L) | `clear` |
| `pwd` | Show the current folder | `pwd` |
| `cd <folder>` | Change folder (stays inside the project) | `cd src` · `cd ..` · `cd` |
| `open <file>[:line]` / `code` | Open a file in the editor | `open src/app.js:42` |
| `run [file]` | Run / preview the file (like ▶) | `run index.html` |
| `node <file.js> [args]` | Run JavaScript in V8 (no npm modules) | `node main.js hello` |
| `node -e "<code>"` | Run a line of JavaScript | `node -e "console.log(2**10)"` |
| `node -p "<expr>"` | Print an expression | `node -p "new Date()"` |
| `serve [file]` / `preview` | Start the live preview | `serve` |
| `search <text> [--regex] [--case]` / `rg` | Find in all project files | `search fetch(` |
| `tree [folder]` | Show the folder tree | `tree src` |
| `history` | Commands you ran | `history` |
| `env` | Environment variables | `env` |
| `nova <question>` / `ai` | Ask NOVA Coder (Premium) | `nova explain utils.js` |
| `agent <task>` | Let NOVA Agent change the project | `agent add a footer` |
| `guide [section]` / `man` / `docs` | Open this guide | `guide terminal` |

### Shell tools (Android toybox)
| Command | What it does | Example |
|---|---|---|
| `ls` | List files (`-l` details, `-a` hidden, `-h` sizes) | `ls -lah` |
| `cat` | Print a file | `cat package.json` |
| `head` / `tail` | First / last lines | `tail -n 20 app.log` |
| `wc` | Count lines, words, bytes | `wc -l *.js` |
| `grep` | Search text (`-r` recursive, `-n` line numbers, `-i` ignore case) | `grep -rn "TODO" .` |
| `find` | Find files | `find . -name "*.css"` |
| `sed` | Edit text in a stream / in place | `sed -i 's/old/new/g' a.txt` |
| `sort` / `uniq` | Sort lines / remove duplicates | `sort -u names.txt` |
| `diff` | Compare two files | `diff old.js new.js` |
| `mkdir -p` | Create folders | `mkdir -p src/components` |
| `touch` | Create an empty file | `touch notes.md` |
| `cp` / `cp -r` | Copy files / folders | `cp -r src backup` |
| `mv` | Move / rename | `mv a.js b.js` |
| `rm` / `rm -r` | Delete files / folders (careful!) | `rm -r build` |
| `echo` | Print text, write files with `>` / `>>` | `echo "hi" > a.txt` |
| `md5sum` / `sha256sum` | File checksums | `sha256sum app.zip` |
| `base64` | Encode / decode (`-d`) | `base64 logo.png > logo.txt` |
| `du -sh` | Folder size | `du -sh *` |
| `date` | Date and time | `date` |
| `ping -c 3` | Reachability of a host | `ping -c 3 google.com` |
| `xxd` / `od` | Hex dump | `xxd icon.png` |
| `tar` / `unzip` | Archives | `unzip theme.zip` |

You can combine commands with pipes `|`, redirects `>` `>>`, and `&&` / `||`.

### Not available on a stock phone
`npm`, `npx`, `yarn`, `pip`, `python`, `git`, `php`, `java`, `apt`, `sudo`, `vim`/`nano`. X Coder tells you what to use instead (e.g. **node** for JavaScript, **Export .zip** + a computer for git, a server for PHP/Python).
''',
  ),
  GuideSection(
    id: 'shortcuts',
    tab: 'Shortcuts',
    title: 'Keyboard shortcuts',
    subtitle: 'Hardware keyboard, DeX, Chromebook',
    icon: Icons.keyboard_rounded,
    color: Color(0xFFB39DDB),
    body: r'''
| Keys | Action |
|---|---|
| **Ctrl+S** | Save |
| **Ctrl+P** | Go to file |
| **Ctrl+Shift+P** | Command palette |
| **F1** | Developer Guide |
| **F5 / Ctrl+Enter** | Run / preview |
| **Ctrl+backtick** | Toggle terminal |
| **Ctrl+I** | NOVA Coder |
| **Ctrl+Shift+I** | NOVA Agent |
| **Alt+\** | AI completion at the cursor |
| **Ctrl+Shift+F** | Find in files |
| **Ctrl+F / Ctrl+H** | Find / replace in file |
| **Shift+Alt+F** | Format document |
| **Ctrl+/** | Toggle comment |
| **Ctrl+D** | Add next occurrence (multi-cursor) |
| **Alt+↑ / Alt+↓** | Move line up / down |
| **Ctrl+Shift+K** | Delete line |
| **Ctrl+Z / Ctrl+Y** | Undo / redo |
| **Ctrl+Space** | Show suggestions |
| **Ctrl+L** (terminal) | Clear |
| **Ctrl+C** (terminal) | Stop the running program |
''',
  ),
  GuideSection(
    id: 'devtools',
    tab: 'Dev Tools',
    title: 'Dev Tools',
    subtitle: 'Inspect and debug any website',
    icon: Icons.developer_mode_rounded,
    color: Color(0xFF26C6DA),
    body: r'''
Open a page in the browser, then **⋮ › Developer tools**. The panel docks under the page — drag the top bar to resize (⤢ for full height). ⌖ picks an element by tapping the page; ↻ reloads.

### Elements
- The live DOM tree (shadow roots included). Tap ⌖, then tap anything on the page to jump to it.
- **Find** by text or CSS selector (`#id`, `.class`, `nav a`).
- For the selected element: **Styles** (matched CSS rules with their file and @media, edit the inline style), **Computed** values with colour swatches, **Box** model, **Attributes** (tap to edit, ✕ to remove, add new), **HTML** (*Edit as HTML*), **A11y** (role, accessible name).
- **⋯ menu:** scroll into view, click, hide, duplicate, delete, copy selector / XPath / outerHTML, use as **$0** in the console.

### Console
- All `console.*` messages with their **file:line**, errors with stack (tap), failed loads, CSP violations.
- Filter by level, search, and the **↓ New messages** bar when you scroll up.
- **Run JavaScript** on the page: `document.title`, `$0.style.color = 'red'`, `$$('a').length`, `await fetch('/api').then(r => r.json())`. Objects expand ▸. Helpers: `$0`, `$()`, `$$()`, `$x()`, `clear()`. Ctrl+Enter runs; ⟲ recalls history.

### Sources
- Every file the page loaded, grouped by domain and folder, plus inline `<script>` / `<style>` blocks.
- Opens in a code viewer: **{ } pretty-print** minified files, find, word wrap, go to line, copy, **Edit in X Coder**.
- Files from other domains are downloaded by the app when the page can't read them.

### Network
- fetch / XHR / WebSocket requests live, plus everything the browser loaded (scripts, CSS, images, fonts).
- Filters (Fetch/XHR, Doc, JS, CSS, Img, Font, WS, Errors), search, waterfall bars, totals.
- Tap a request: **Headers**, query string, **Payload** (form/raw), **Response** (JSON tree or raw), WebSocket **Messages**, **Timing**. ⋮ → *Copy as cURL*, *Copy as fetch*, *Replay*.
- Headers and bodies are recorded **after Dev Tools is opened** on that tab — tap ↻ to reload and capture everything from the start.

### Application
Local & session storage (add, edit, swipe ← to delete, clear), **all cookies** of the site (HttpOnly marked), IndexedDB records, Cache Storage, service workers (update / unregister), web app manifest (installability checks, icons), storage usage and **Clear site data**.

### Performance
Core Web Vitals rated *Good / Needs work / Poor*: **LCP, CLS, FCP, TTFB, TBT**, load time, the **LCP element** (tap to highlight), navigation timeline, resources by type, slowest requests, DOM size, JS memory. *Reload & measure* for a clean run.

### Audit
Lighthouse-style scores for **Performance, Accessibility** (incl. colour contrast), **Best Practices, SEO, PWA**, plus **Security**: TLS certificate and security headers (HSTS, CSP, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy). Tap a finding to highlight the element.

### Device
User-agent presets (Android, iPhone, iPad, Windows, macOS, Firefox, Googlebot, custom), desktop layout, JavaScript / images / cache on-off, force dark, text zoom, clear cache & hard reload, and page facts (frameworks detected, viewport, DPR, element counts).

### Tools
JSON formatter/validator/tree, JWT decoder (expiry check), Base64, URL encode/decode/parse, Unix timestamps, regex tester (flags, groups, highlights), colour converter + contrast, UUID v4, HTML entities, text diff — all offline.
''',
  ),
  GuideSection(
    id: 'browser',
    tab: 'Browser',
    title: 'Browser features for developers',
    subtitle: 'In the ⋮ menu of any tab',
    icon: Icons.public_rounded,
    color: Color(0xFF66BB6A),
    body: r'''
| Feature | Use it to… |
|---|---|
| **Request desktop site** | Test the desktop layout of a site |
| **Find in page** | Search text on the page |
| **Reader Mode** | Read articles without clutter |
| **Cookie Editor** | View, edit and delete the site's cookies |
| **Clear page data** | Reset cookies & storage for the site |
| **Ad Blocker** | Test how a site behaves with ads blocked |
| **Ask NOVA about this page / Summarise with NOVA** | Explain an API doc, summarise a changelog |
| **Screenshot & record** | Capture the visible part or the full page |
| **New incognito tab** | Test without cookies or history |
| **Developer tools** | See the Dev Tools section |
| **NOVA Cyber** | Scan the site's security |

**Tip:** in X Coder's preview use **⋮ › Open in NOVA X browser** to debug your own page with Dev Tools.
''',
  ),
  GuideSection(
    id: 'cyber',
    tab: 'NOVA Cyber',
    title: 'NOVA Cyber',
    subtitle: 'Website security scanner · OWASP Top 10',
    icon: Icons.security_rounded,
    color: Color(0xFFFF5370),
    body: r'''
Enter a domain or URL (e.g. `example.com`) and tap **Scan**, or use **⋮ › NOVA Cyber** on an open page.

### What it checks
- **HTTPS & TLS:** HTTPS enforced, mixed content, login forms over HTTP.
- **Security headers:** CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, CORS misconfiguration.
- **Cookies:** Secure, HttpOnly and SameSite flags.
- **Exposed files:** `.git`, `.env`/config files, backups, SQL dumps, `phpinfo`, server-status, source maps, directory listing, admin and debug panels, API docs.
- **Injection & content:** reflected XSS, open redirects, inline scripts, emails / internal IPs / JWTs in responses.
- **Recon:** technology stack (server, CMS, frameworks), CDN/WAF detection, outdated JavaScript libraries.

### Reading the report
- **Grade A–F and score /100**, overall risk, and the **OWASP Top 10** categories that were hit.
- Each finding has **status** (PASS / WARN / FAIL), **severity** (Critical → Info), **evidence** (long-press to copy) and a **fix**.
- **Recommendations** list the most valuable fixes first. Copy the full report to share it with your team.

> Scan only sites you own or are allowed to test. NOVA Cyber sends ordinary requests (like a browser); it doesn't attack sites.
''',
  ),
  GuideSection(
    id: 'shield',
    tab: 'NOVA Shield',
    title: 'NOVA Shield',
    subtitle: 'Privacy & security engine of the browser',
    icon: Icons.shield_outlined,
    color: Color(0xFF00C853),
    body: r'''
NOVA Shield protects browsing in NOVA X (it doesn't change other apps' traffic).

| Layer | What it does |
|---|---|
| **Encrypted DNS (DoH)** | Domain lookups are encrypted. Choose the provider: Cloudflare, Cloudflare + malware blocking (default), NOVA DNS Maximum (multi-source threat intelligence), Google (Pro: choice of provider) |
| **Malware blocking** | Domains are checked against live threat feeds before the page loads |
| **HTTPS enforcement** | `http://` links are upgraded to `https://` |
| **IP-leak prevention** (Pro) | Stops WebRTC from revealing your real IP |
| **Fingerprint protection** (Pro) | Adds noise to canvas, audio and screen values |
| **Referrer privacy** (Pro) | Hides which page you came from |

The dashboard shows a **protection score** and stats (malware blocked, HTTPS upgrades, IP leaks blocked, DNS queries encrypted) — counted on your phone only. **Reset stats** clears them.

**For developers:** if a local or test site doesn't load, check whether HTTPS enforcement or malware blocking stopped it (turn NOVA Shield off for the test), and remember fingerprint noise can change canvas results.
''',
  ),
  GuideSection(
    id: 'network',
    tab: 'NOVA Network',
    title: 'NOVA Network',
    subtitle: 'Speed test & device details',
    icon: Icons.network_check_rounded,
    color: Color(0xFF29B6F6),
    body: r'''
- **Speed test:** download, upload, **latency** (ping & jitter) and **bufferbloat** (how latency rises under load) — the numbers that decide how fast an app *feels*. History is saved on your phone.
- **Device & connection:** IP address, provider, approximate location (city level), connection type, battery and storage.
- Ask NOVA: *"what's my internet speed"*, *"my ping"*, *"my IP address"*.

**For developers:** test your app on a slow connection by comparing results on Wi-Fi vs mobile data, and use Dev Tools › Performance on the same network to see how TTFB and LCP change.
''',
  ),
  GuideSection(
    id: 'capture',
    tab: 'NOVA Capture',
    title: 'NOVA Capture',
    subtitle: 'Screenshots & screen recordings',
    icon: Icons.videocam_outlined,
    color: Color(0xFFFF7043),
    body: r'''
- **Screenshots:** the whole screen, the visible web page, or the **full page** (scrolls and stitches). Edit with crop, rotate, draw, arrows, text, blur/redact.
- **Screen recording:** up to 1080p / 60 fps where the phone supports it, with **no sound, microphone, app sound or both**. Pause/resume, countdown, time limit.
- **Floating capture button:** turn it on in NOVA Capture to record / pause / stop / screenshot over any app — handy for bug reports and demos. Drag it onto ✕ to close it.
- **By voice:** *"Hey NOVA, start recording"*, *"take a screenshot"*, *"stop recording"*.
- Everything is saved only on your phone (Pictures/NOVA X, Movies/NOVA X).
''',
  ),
  GuideSection(
    id: 'offline',
    tab: 'Offline & privacy',
    title: 'Offline & privacy',
    subtitle: 'What works without internet, what leaves the phone',
    icon: Icons.cloud_off_rounded,
    color: Color(0xFF90A4AE),
    body: r'''
### Works offline
X Coder (editor, suggestions, linting, terminal, `node`, preview), this guide, Dev Tools Tools tab, saved news, quick-access icons, business listings and NOVA AI chats you've opened before, coin balance (last known), NOVA Music, screenshots and recordings.

### Needs internet
NOVA Coder & Agent, NOVA AI answers, NOVA Cyber scans, speed tests, new news and listings.

### Privacy
- Your projects and files stay on your phone. Dev Tools data stays in the app's memory for that tab.
- NOVA Coder receives only what it needs for a request (the open file/selection, other open tabs, the file list, errors) and doesn't store it.
- Never paste real API keys or passwords into code you send to AI — use placeholders like `YOUR_API_KEY`.
''',
  ),
  GuideSection(
    id: 'faq',
    tab: 'Troubleshooting',
    title: 'Troubleshooting',
    subtitle: 'Quick answers',
    icon: Icons.help_outline_rounded,
    color: Color(0xFFFFCB6B),
    body: r'''
**The preview shows an old version.** Save (Ctrl+S) — the preview reloads on save. Or ⋮ › *Clear cache & reload*.

**"npm: not available".** Phones have no npm. Use plain JavaScript with `node`, CDN `<script>` tags in HTML, or export the project (.zip) and build on a computer.

**Dev Tools Network shows no headers/bodies.** They're recorded after Dev Tools is opened on the tab — tap ↻ in Dev Tools to reload and capture.

**Sources can't open a file.** Some servers block downloads without a browser session; open the file's URL in a tab, or check Network › Response.

**NOVA Coder says "Sign in" or "Premium".** NOVA Coder needs a signed-in NOVA X account with Premium.

**NOVA Coder is busy.** Many developers are using it at once — try again in a few seconds; your request is never charged twice.

**The agent's change didn't apply ("text not found").** The file changed after the plan was made. Ask the agent again; it will re-read the file.

**The terminal command hangs.** Press **^C**. Commands are stopped automatically after 5 minutes.

**Formatting does nothing.** Formatting supports HTML, CSS, JS/TS, JSON, PHP and XML; wait a second after opening a file (the language loads first).
''',
  ),
];
