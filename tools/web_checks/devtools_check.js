const fs = require('fs'), path = require('path'), os = require('os');
const { ROOT, chromium, check, done, dartRaw, serve } = require('./common');
const hook = dartRaw('lib/features/browser/devtools/devtools_hooks.dart', 'kDevtoolsHook');
const site = fs.mkdtempSync(path.join(os.tmpdir(), 'nxdt-'));
fs.writeFileSync(path.join(site, 'index.html'), `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DevTools test page</title><link rel="stylesheet" href="s.css"><style>.card{padding:10px;margin:4px;border:2px solid red} #low{color:#ccc;background:#fff}</style>
<script src="app.js"></script></head><body><h1>Hello</h1><div class="card" id="c1"><p>Para</p><img src="missing.png"><button></button></div>
<p id="low">low contrast text</p><input id="in"><script>console.log('inline', {a:1}); localStorage.setItem('k','v');</script>
<div id="host"></div><script>document.getElementById('host').attachShadow({mode:'open'}).innerHTML='<span>shadow</span>';</script></body></html>`);
fs.writeFileSync(path.join(site, 's.css'), '.card{color:blue}');
fs.writeFileSync(path.join(site, 'app.js'), 'console.warn("app loaded"); fetch("data.json").then(r=>r.json()); var x=new XMLHttpRequest(); x.open("POST","data.json"); x.setRequestHeader("X-T","1"); x.send("a=1"); setTimeout(function(){ null.y },10)');
fs.writeFileSync(path.join(site, 'data.json'), '{"ok":true}');
(async () => {
  const srv = await serve(site, 8792, { 'x-frame-options': 'DENY' });
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 400, height: 800 } }); const ev = [];
  await p.exposeFunction('__ev', (n, o) => ev.push([n, o]));
  await p.addInitScript(() => { window.flutter_inappwebview = { callHandler: (n, o) => window.__ev(n, o) }; window.__nxdtArmed = true; });
  await p.addInitScript(hook);
  await p.goto('http://localhost:8792/'); await p.waitForTimeout(800);
  await p.evaluate(fs.readFileSync(path.join(ROOT, 'assets/devtools/nxdt_agent.js'), 'utf8'));
  const A = (fn, arg) => p.evaluate(async ([fn, arg]) => JSON.parse(JSON.stringify(await window.__nxdt[fn](arg))), [fn, arg]);
  const logs = ev.filter(e => e[0] === 'novaxLog').map(e => e[1]);
  check('console messages with source', logs.some(l => l.type === 'warn' && l.src === 'app.js:1'));
  check('uncaught errors', logs.some(l => l.type === 'error' && /^Uncaught TypeError/.test(l.msg) && !/Uncaught Uncaught/.test(l.msg)));
  check('failed resource loads', logs.some(l => l.msg.includes('missing.png')));
  const net = ev.filter(e => e[0] === 'novaxNet' && e[1].phase === 'end').map(e => e[1]);
  const xhr = net.find(n => n.type === 'xhr'), fet = net.find(n => n.type === 'fetch');
  check('XHR captured with headers and bodies (armed)', xhr && xhr.reqBody === 'a=1' && xhr.reqHeaders['x-t'] === '1' && xhr.resBody.includes('ok'));
  check('fetch captured', fet && fet.status === 200 && fet.resBody.includes('ok'));
  const body = await A('children', [1]);
  const host = body.nodes.find(n => n.attrs && n.attrs.some(a => a[1] === 'host'));
  check('DOM tree incl. shadow root', (await A('children', host.path)).nodes.some(n => n.tag === 'span' && n.inShadow));
  const c1 = body.nodes.find(n => n.attrs && n.attrs.some(a => a[1] === 'c1')).path;
  const d = await A('details', c1);
  check('element details: selector, matched rules, box model', d.selector === '#c1' && d.rules.length === 2 && d.box.padding[0] === 10);
  check('edit attribute', (await A('edit', { path: c1, op: 'setAttr', name: 'data-x', value: '1' })).ok);
  check('local storage', (await A('storage', 'local')).items.some(i => i[0] === 'k'));
  const res = await A('resources');
  check('sources list', ['s.css', 'app.js'].every(f => res.items.some(i => i.url.endsWith(f))) && res.inline.length >= 2);
  check('fetch source text', (await A('fetchText', 'http://localhost:8792/s.css')).text === '.card{color:blue}');
  const perf = await A('perf');
  check('performance metrics', typeof perf.fcp === 'number' && perf.dom > 10);
  const au = await A('audit');
  const failed = au.audits.filter(a => !a.pass).map(a => a.id);
  check('audit finds missing alt, button name, label, contrast', ['image-alt', 'button-name', 'label', 'color-contrast'].every(i => failed.includes(i)), failed);
  check('security headers read', (await A('securityHeaders')).headers['x-frame-options'] === 'DENY');
  check('clear site data', (await A('clearSite')).done.includes('local storage'));
  await b.close(); srv.close(); fs.rmSync(site, { recursive: true }); done();
})();
