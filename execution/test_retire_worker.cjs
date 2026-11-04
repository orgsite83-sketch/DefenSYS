const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const handlers = {}, events = [];
const context = {self: {
  addEventListener: (name, fn) => handlers[name] = fn,
  skipWaiting: async () => events.push('skipWaiting'),
  clients: {claim: async () => events.push('claim')},
  registration: {unregister: async () => events.push('unregister')},
}, caches: {delete: async name => events.push(name)}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../deployment/web/retire_flutter_service_worker.js'), 'utf8'), context);
(async () => {
  const run = async name => {let pending; handlers[name]({waitUntil: p => pending = p}); await pending;};
  await run('install'); await run('activate');
  assert.deepEqual(events, ['skipWaiting', 'flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest', 'claim', 'unregister']);
  assert.equal(handlers.fetch, undefined);
  assert.equal(context.localStorage, undefined);
  console.log('Retirement lifecycle passed: no automatic navigation or user-storage access.');
})().catch(error => {console.error(error); process.exitCode = 1;});
