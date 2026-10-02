// Run: node scripts/keepalive-regression.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const source = fs.readFileSync(path.resolve(__dirname, '../command/Resources/JavaScript/naki-core.js'), 'utf8');

function setup({ top = true, visibility = 'visible' } = {}) {
  const env = { visibility, rafQueue: [], timers: [], listeners: [], pageEvents: 0, errors: [] };
  function Document() {}
  Object.defineProperty(Document.prototype, 'visibilityState', { configurable: true, get() { return env.visibility; } });
  Object.defineProperty(Document.prototype, 'hidden', { configurable: true, get() { return env.visibility === 'hidden'; } });
  const document = Object.create(Document.prototype);
  document.addEventListener = (type, fn, capture) => env.listeners.push({ type, fn, capture });
  const c = { Document, document, performance: { now: () => 1234 }, Map,
    console: { log() {}, error: (...a) => env.errors.push(a) },
    requestAnimationFrame: cb => env.rafQueue.push(cb),
    setTimeout: (fn, ms) => { env.timers.push({ fn, ms }); return env.timers.length; },
    clearTimeout: id => { env.timers[id - 1] = null; } };
  c.window = c; c.top = top ? c : {};
  vm.createContext(c); vm.runInContext(source, c);
  env.c = c;
  env.frame = ts => { const q = env.rafQueue; env.rafQueue = []; q.forEach(f => f(ts)); };
  env.tick = () => { const t = env.timers.filter(Boolean); env.timers = []; t.forEach(x => x.fn()); };
  // 模擬瀏覽器分派 visibilitychange：先跑我們註冊的 capture listener，被擋下才不進頁面 listener
  env.fireVisibility = to => {
    env.visibility = to;
    let stopped = false;
    const e = { stopImmediatePropagation() { stopped = true; } };
    env.listeners.forEach(l => { if (!stopped && l.type === 'visibilitychange') l.fn(e); });
    if (!stopped) env.pageEvents++;
  };
  return env;
}

test('visible: one flush per frame, cancel works, no double calls', () => {
  const e = setup(); const calls = [];
  const a = e.c.requestAnimationFrame(t => calls.push(['a', t]));
  e.c.requestAnimationFrame(t => calls.push(['b', t]));
  const x = e.c.requestAnimationFrame(() => calls.push(['x']));
  e.c.cancelAnimationFrame(x);
  assert.equal(e.rafQueue.length, 1);
  assert.equal(e.timers.filter(Boolean).length, 0);
  e.frame(16);
  assert.deepEqual(calls, [['a', 16], ['b', 16]]);
  e.frame(32);
  assert.equal(calls.length, 2);
  assert.notEqual(a, undefined);
});

test('hidden + enabled: timer drives flush and keeps looping', () => {
  const e = setup({ visibility: 'hidden' }); let n = 0;
  const loop = () => { n++; e.c.requestAnimationFrame(loop); };
  e.c.requestAnimationFrame(loop);
  assert.equal(e.c.__nakiKeepAlive.state().pumping, true);
  e.tick(); e.tick(); e.tick();
  assert.equal(n, 3);
  assert.equal(e.c.__nakiKeepAlive.state().flushCount, 3);
});

test('visible -> hidden with queued callbacks starts the pump via visibilitychange', () => {
  const e = setup(); let n = 0;
  e.c.requestAnimationFrame(() => n++);
  assert.equal(e.c.__nakiKeepAlive.state().pumping, false);
  e.fireVisibility('hidden');
  assert.equal(e.c.__nakiKeepAlive.state().pumping, true);
  e.tick(); assert.equal(n, 1);
  e.fireVisibility('visible');
  assert.equal(e.c.__nakiKeepAlive.state().pumping, false);
});

test('hidden + disabled: nothing flushes, pump stopped', () => {
  const e = setup({ visibility: 'hidden' }); let n = 0;
  e.c.requestAnimationFrame(() => n++);
  e.c.__nakiKeepAlive.set(false);
  assert.equal(e.c.__nakiKeepAlive.state().pumping, false);
  e.tick(); assert.equal(n, 0);
  e.frame(1); assert.equal(n, 1);
  e.c.__nakiKeepAlive.set(true);
  e.c.requestAnimationFrame(() => n++);
  assert.equal(e.c.__nakiKeepAlive.state().pumping, true);
});

test('document.hidden / visibilityState override follows enabled; events gated', () => {
  const e = setup({ visibility: 'hidden' });
  assert.equal(e.c.document.hidden, false);
  assert.equal(e.c.document.visibilityState, 'visible');
  e.fireVisibility('hidden'); assert.equal(e.pageEvents, 0);
  e.c.__nakiKeepAlive.set(false);
  assert.equal(e.c.document.hidden, true);
  assert.equal(e.c.document.visibilityState, 'hidden');
  e.fireVisibility('hidden'); assert.equal(e.pageEvents, 1);
  assert.equal(e.c.__nakiKeepAlive.state().reallyHidden, true);
});

test('a throwing callback is rethrown outside the batch and does not stop the others', () => {
  const e = setup({ visibility: 'hidden' }); let ok = 0;
  e.c.requestAnimationFrame(() => { throw new Error('boom'); });
  e.c.requestAnimationFrame(() => ok++);
  e.tick();
  assert.equal(ok, 1);
  assert.throws(() => e.tick(), /boom/);
});

test('visible: a throwing callback is also rethrown', () => {
  const e = setup();
  e.c.requestAnimationFrame(() => { throw new Error('vis'); });
  e.frame(1);
  assert.throws(() => e.tick(), /vis/);
});

test('cancelAnimationFrame inside a running batch cancels later callbacks', () => {
  const e = setup(); const calls = []; let idB;
  e.c.requestAnimationFrame(() => { calls.push('a'); e.c.cancelAnimationFrame(idB); });
  idB = e.c.requestAnimationFrame(() => calls.push('b'));
  e.c.requestAnimationFrame(() => calls.push('c'));
  e.frame(1);
  assert.deepEqual(calls, ['a', 'c']);
});

test('tick: hidden + enabled flushes once and returns true', () => {
  const e = setup({ visibility: 'hidden' }); let n = 0;
  const loop = () => { n++; e.c.requestAnimationFrame(loop); };
  e.c.requestAnimationFrame(loop);
  assert.equal(e.c.__nakiKeepAlive.tick(), true);
  assert.equal(n, 1);
  assert.equal(e.c.__nakiKeepAlive.tick(), true);
  assert.equal(n, 2);
});

test('tick: visible does not flush and returns false; disabled does not flush', () => {
  const e = setup(); let n = 0;
  e.c.requestAnimationFrame(() => n++);
  assert.equal(e.c.__nakiKeepAlive.tick(), false);
  assert.equal(n, 0);
  e.fireVisibility('hidden');
  e.c.__nakiKeepAlive.set(false);
  assert.equal(e.c.__nakiKeepAlive.tick(), true);
  assert.equal(n, 0);
});

test('non-top frame installs nothing', () => {
  const e = setup({ top: false });
  assert.equal(e.c.__nakiKeepAlive, undefined);
  assert.equal(e.listeners.length, 0);
  assert.equal(e.c.document.hidden, false);
});
