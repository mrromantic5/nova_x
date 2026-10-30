const { chromium, check, done, dartRaw } = require('./common');
const harness = dartRaw('lib/features/xcoder/run/js_runner.dart', '_harness');
(async () => {
  const b = await chromium.launch();
  async function run(code) {
    const p = await b.newPage(); const lines = []; let fin; const f = new Promise(r => fin = r);
    await p.exposeFunction('__ev', o => { if (o.text) lines.push(o.level + ': ' + o.text); if (o.done) fin(); });
    await p.evaluate(() => { window.flutter_inappwebview = { callHandler: (n, o) => window.__ev(o) }; });
    await p.evaluate(([h, code]) => { (new Function('code', 'file', 'args', 'return (async function(){' + h + '})()'))(code, 'main.js', []); }, [harness, code]);
    await Promise.race([f, new Promise(r => setTimeout(r, 3000))]); await p.close(); return lines;
  }
  let l = await run("console.log(`Hello, ${'X'}!`); console.table([{a:1}])");
  check('console.log + console.table', l[0] === 'log: Hello, X!' && l[1].includes('│ (index) │ a │'), l);
  l = await run("setTimeout(()=>console.log('later'),100); (async()=>{await null; console.warn('async')})()");
  check('timers and async finish before the run ends', l.join('|') === 'warn: async|log: later', l);
  l = await run('null.x');
  check('errors show the user file and line', l[0].startsWith('error: Uncaught TypeError') && l[0].includes('main.js:1'), l);
  l = await run("require('fs')");
  check('require explains it is not Node.js', l[0].includes("isn't available"), l);
  l = await run("console.log(1); process.exit(0); console.log(2)");
  check('process.exit stops the script', l.join('|') === 'log: 1|info: process.exit(0)', l);
  await b.close(); done();
})();
