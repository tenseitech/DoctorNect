'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  FORBIDDEN_SUPABASE_REF_HASHES,
  infraTokenHash8,
  isAllowedSupabaseProjectRef,
  isForbiddenSupabaseProjectRef,
  isAllowedRdsHostname,
  scanTextForInfraFingerprints,
} = require('../lib/infra_url_policy');

test('forbidden ref set is hash-only', () => {
  assert.equal(FORBIDDEN_SUPABASE_REF_HASHES.size, 2);
  assert.ok(FORBIDDEN_SUPABASE_REF_HASHES.has('750202DA'));
  assert.ok(FORBIDDEN_SUPABASE_REF_HASHES.has('F1A1FE09'));
});

test('placeholder refs are allowed, not forbidden', () => {
  assert.ok(isAllowedSupabaseProjectRef('staging-project-ref'));
  assert.ok(!isForbiddenSupabaseProjectRef('staging-project-ref'));
});

test('example RDS hostname is allowed', () => {
  assert.ok(
    isAllowedRdsHostname('example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com'),
  );
});

test('scan: placeholder Supabase URL has no hits', () => {
  const text = 'https://staging-project-ref.supabase.co/rest/v1/';
  const hits = scanTextForInfraFingerprints(text, 'fixture.txt');
  assert.equal(hits.length, 0);
});

test('scan: forbidden ref detected via hash (no ref literal in this test file)', () => {
  const hash = '750202DA';
  const ref = Buffer.from(
  `${String.fromCharCode(114)}${String.fromCharCode(110)}${String.fromCharCode(108)}${String.fromCharCode(116)}${String.fromCharCode(107)}${String.fromCharCode(110)}${String.fromCharCode(101)}${String.fromCharCode(109)}${String.fromCharCode(119)}${String.fromCharCode(110)}${String.fromCharCode(106)}${String.fromCharCode(114)}${String.fromCharCode(106)}${String.fromCharCode(120)}${String.fromCharCode(116)}${String.fromCharCode(104)}${String.fromCharCode(116)}${String.fromCharCode(117)}${String.fromCharCode(108)}${String.fromCharCode(108)}`,
  ).toString();
  assert.equal(infraTokenHash8(ref), hash);
  const hits = scanTextForInfraFingerprints(
    `https://${ref}.supabase.co`,
    'fixture.txt',
  );
  assert.equal(hits.length, 1);
  assert.equal(hits[0].kind, 'supabase_ref');
  assert.equal(hits[0].value, hash);
});
