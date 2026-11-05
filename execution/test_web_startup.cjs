// Exercise the real startup document against the legacy worker's cache key rules.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'frontend/web/index.html'), 'utf8');
const code = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).find(script => script.includes("searchParams.set('startup',"));
assert.ok(code, 'Startup must bypass a cached bare bootstrap URL');
const scripts = [];
vm.runInNewContext(code, {URL, Date, document: {
  baseURI: 'https://defensys.site/',
  createElement: tag => {assert.equal(tag, 'script'); return {};},
  body: {appendChild: script => scripts.push(script)},
}});
assert.equal(scripts.length, 1);
const url = new URL(scripts[0].src);
assert.equal(url.pathname, '/flutter_bootstrap.js');
assert.ok(url.searchParams.has('startup'));
// The old worker only strips ?v=; our startup key must not match RESOURCES.
const key = (url.pathname.slice(1) + url.search).split('?v=')[0];
assert.notEqual(key, 'flutter_bootstrap.js');
assert.equal(scripts[0].async, true);
console.log('Startup bypasses the legacy cached bootstrap without clearing user storage or reloading.');
