'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { loadBrowserModule } = require('./helpers/load-browser-module.js');

const MODULE_PATH = path.join(
  __dirname, '..', '..', 'Sources', 'Baguette', 'Resources', 'Web',
  'defaults', 'preference-rows.js'
);

function Rows() {
  return loadBrowserModule(MODULE_PATH).Baguette._PreferenceRows;
}

test('a read becomes one row per key, in key order, each with the control its type needs', () => {
  const rows = Rows().fromRead({
    bundleId: 'com.x',
    values: {
      username: { type: 'string', value: 'ada' },
      onboarded: { type: 'bool', value: false },
      launches: { type: 'int', value: 3 },
      ratio: { type: 'float', value: 2 },
      syncedAt: { type: 'date', value: '2026-01-02T03:04:05Z' },
    },
  });
  assert.deepEqual(rows.map((r) => [r.key, r.type, r.control]), [
    ['launches', 'int', 'text'],
    ['onboarded', 'bool', 'switch'],
    ['ratio', 'float', 'text'],
    ['syncedAt', 'date', 'text'],
    ['username', 'string', 'text'],
  ]);
  assert.equal(rows[0].text, '3');
  assert.equal(rows[1].checked, false);
  assert.equal(rows[2].text, '2');
});

test('a collection row carries the plist text the server sent, and how many entries it has', () => {
  const [flags, tags] = Rows().fromRead({
    values: {
      tags: { type: 'array', value: [{ type: 'int', value: 1 }], plist: '<array><integer>1</integer></array>' },
      flags: { type: 'dict', value: { a: { type: 'bool', value: true }, b: { type: 'bool', value: false } }, plist: '<dict/>' },
    },
  });
  assert.deepEqual([flags.control, flags.summary, flags.text], ['plist', '2 keys', '<dict/>']);
  assert.deepEqual([tags.control, tags.summary, tags.text], ['plist', '1 item', '<array><integer>1</integer></array>']);
});

test('a data row shows its size, not its bytes', () => {
  const [blob] = Rows().fromRead({ values: { blob: { type: 'data', value: 'A'.repeat(2868) } } });
  assert.deepEqual([blob.control, blob.summary], ['data', '2.1 KB']);
});

test('a read with nothing stored has no rows', () => {
  assert.deepEqual(Rows().fromRead({ bundleId: 'com.x', values: {} }), []);
  assert.deepEqual(Rows().fromRead(null), []);
});

test('a write posts the value as the type it was read as', () => {
  const R = Rows();
  assert.deepEqual(
    R.writeBody({ bundleId: 'com.x', suite: null, key: 'n', type: 'int', value: '4', relaunch: true }),
    { bundleId: 'com.x', key: 'n', type: 'int', value: '4', relaunch: true }
  );
  assert.deepEqual(
    R.writeBody({ bundleId: 'com.x', suite: 'group.x', key: 'seen', type: 'bool', value: false, relaunch: false }),
    { bundleId: 'com.x', suite: 'group.x', key: 'seen', type: 'bool', value: false, relaunch: false }
  );
});

test('a collection is written back as plist text', () => {
  assert.deepEqual(
    Rows().writeBody({ bundleId: 'com.x', key: 'tags', type: 'array', value: '<array/>', relaunch: false }).type,
    'plist'
  );
  assert.equal(
    Rows().writeBody({ bundleId: 'com.x', key: 'flags', type: 'dict', value: '<dict/>', relaunch: false }).type,
    'plist'
  );
});

test('the read, delete and groups queries name the app, the suite and the key', () => {
  const R = Rows();
  assert.equal(R.query({ bundleId: 'com.x', suite: null, plist: true }), 'bundleId=com.x&plist=1');
  assert.equal(
    R.query({ bundleId: 'com.x', suite: 'group.a&b', key: 'k y', relaunch: true }),
    'bundleId=com.x&suite=group.a%26b&key=k%20y&relaunch=1'
  );
});

test('an import posts the values of an export, or a bare map as it is', () => {
  const R = Rows();
  const values = { seen: { type: 'bool', value: false } };
  assert.deepEqual(
    R.importBody({ bundleId: 'com.x', suite: null, file: { bundleId: 'com.y', values }, relaunch: true }),
    { bundleId: 'com.x', values, relaunch: true }
  );
  assert.deepEqual(
    R.importBody({ bundleId: 'com.x', suite: 'group.x', file: values, relaunch: false }),
    { bundleId: 'com.x', suite: 'group.x', values, relaunch: false }
  );
});

test('an export file is named for the app and suite it came from', () => {
  const R = Rows();
  assert.equal(R.exportFileName({ bundleId: 'com.x', suite: null }), 'com.x.defaults.json');
  assert.equal(R.exportFileName({ bundleId: 'com.x', suite: 'group.x' }), 'com.x.group.x.defaults.json');
});

test('a failure reads as a card-level notice by its HTTP status', () => {
  const R = Rows();
  assert.deepEqual(R.notice(409, 'the simulator is not booted (run `baguette boot`)'),
    { tone: 'danger', text: 'the simulator is not booted (run `baguette boot`)', action: 'boot' });
  assert.deepEqual(R.notice(404, 'com.x has no App Group group.y'),
    { tone: 'warn', text: 'com.x has no App Group group.y', action: null });
  assert.deepEqual(R.notice(500, ''), { tone: 'danger', text: 'Request failed (500)', action: null });
});
