'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('Migration 20261008000003: Safely drops users_id_fkey without destructive statements', () => {
  const migrationPath = path.resolve(
    __dirname,
    '../../supabase/migrations/20261008000003_allow_firebase_users_drop_fkey.sql'
  );

  assert.ok(fs.existsSync(migrationPath), 'Migration 20261008000003 must exist');

  const content = fs.readFileSync(migrationPath, 'utf8');

  // Must drop users_id_fkey safely
  assert.match(
    content,
    /ALTER\s+TABLE\s+public\.users\s+DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+users_id_fkey/i,
    'Migration must drop users_id_fkey with IF EXISTS guard'
  );

  // Must include rationale explaining Firebase identity
  assert.ok(
    content.toLowerCase().includes('firebase'),
    'Migration header must document Firebase third-party identity rationale'
  );

  // Must include commented rollback section
  assert.match(
    content,
    /--\s*ROLLBACK\s+SECTION/i,
    'Migration must provide a commented rollback section'
  );
  assert.match(
    content,
    /--.*ADD\s+CONSTRAINT\s+users_id_fkey/i,
    'Rollback section must document how to restore users_id_fkey constraint'
  );

  // Parse active (uncommented) lines to verify absence of destructive operations
  const lines = content.split('\n');
  const activeLines = [];
  let inBlockComment = false;

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (inBlockComment) {
      if (trimmed.includes('*/')) {
        inBlockComment = false;
      }
      continue;
    }
    if (trimmed.startsWith('/*')) {
      inBlockComment = true;
      continue;
    }
    if (trimmed.startsWith('--') || trimmed.length === 0) {
      continue;
    }
    // Remove inline comment if present
    const codePart = trimmed.split('--')[0].trim();
    if (codePart.length > 0) {
      activeLines.push(codePart);
    }
  }

  const activeSql = activeLines.join('\n').toUpperCase();

  // Assert no destructive statements
  assert.doesNotMatch(activeSql, /\bDROP\s+TABLE\b/, 'Must NOT contain DROP TABLE');
  assert.doesNotMatch(activeSql, /\bTRUNCATE\b/, 'Must NOT contain TRUNCATE');
  assert.doesNotMatch(activeSql, /\bDELETE\s+FROM\b/, 'Must NOT contain DELETE FROM');
  assert.doesNotMatch(activeSql, /\bDROP\s+SCHEMA\b/, 'Must NOT contain DROP SCHEMA');
  assert.doesNotMatch(activeSql, /\bDROP\s+DATABASE\b/, 'Must NOT contain DROP DATABASE');
  assert.doesNotMatch(activeSql, /\bDROP\s+COLUMN\b/, 'Must NOT contain DROP COLUMN');
});
