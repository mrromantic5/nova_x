const { chromium, check, done, dartFunctionBody, ROOT } = require('./common');
const body = dartFunctionBody('lib/features/browser/devtools/devtools_bridge.dart');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); await p.setContent('<div id=a class="x">hi</div>');
  await p.addScriptTag({ path: ROOT + '/assets/devtools/nxdt_agent.js' });
  const ev = code => p.evaluate(([body, code]) => (new (Object.getPrototypeOf(async function () {}).constructor)('code', body))(code), [body, code]);
  check('expression', (await ev('1+1')).text === '2');
  check('object literal', (await ev('{a:1}')).type === 'object');
  check('statements return the last value', (await ev('var q = 5; q*2')).text === '10');
  check('globals persist', (await ev('q')).text === '5');
  check('top-level await', (await ev('await new Promise(r=>setTimeout(()=>r(42),20))')).text === '42');
  check('await with statements', (await ev('const t = await Promise.resolve(7); t+1')).text === '8');
  check('element preview with path', (await ev('$0 = document.querySelector("#a")')).path !== undefined);
  check('runtime SyntaxError is not run twice', (await ev('window.n=(window.n||0)+1; JSON.parse("x")')).type === 'error' && (await ev('n')).text === '1');
  check('rejected promise', (await ev('Promise.reject(new Error("no"))')).text.startsWith('Uncaught (in promise) Error: no'));
  await b.close(); done();
})();
