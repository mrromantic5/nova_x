// Shared helpers for the web checks.
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = path.resolve(__dirname, '../..');
const { chromium } = require('playwright');
let failures = 0;
function check(name, ok, info) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok || info === undefined ? '' : ' — ' + JSON.stringify(info).slice(0, 300)}`);
  if (!ok) failures++;
}
function done() { console.log(failures ? `\n${failures} failed` : '\nall passed'); process.exit(failures ? 1 : 0); }
/** Raw JS string embedded in a Dart file: `name = r'''…''';` */
function dartRaw(file, name) {
  const s = fs.readFileSync(path.join(ROOT, file), 'utf8');
  const m = s.match(new RegExp(name + "\\s*=\\s*r'''\\n([\\s\\S]*?)''';"));
  if (!m) throw new Error(`${name} not found in ${file}`);
  return m[1];
}
function dartFunctionBody(file) {
  const s = fs.readFileSync(path.join(ROOT, file), 'utf8');
  return s.match(/functionBody: r'''\n([\s\S]*?)''',/)[1];
}
function serve(dir, port, extraHeaders = {}) {
  const types = { html: 'text/html', css: 'text/css', js: 'application/javascript', json: 'application/json' };
  return new Promise(res => {
    const srv = http.createServer((q, r) => {
      let p = decodeURIComponent(q.url.split('?')[0]); if (p === '/') p = '/index.html';
      fs.readFile(path.join(dir, p), (e, d) => {
        if (e) { r.writeHead(404); r.end(); return; }
        r.writeHead(200, { 'content-type': types[p.split('.').pop()] || 'application/octet-stream', ...extraHeaders }); r.end(d);
      });
    }).listen(port, () => res(srv));
  });
}
module.exports = { ROOT, chromium, check, done, dartRaw, dartFunctionBody, serve };
