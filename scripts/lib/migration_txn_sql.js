'use strict';

/**
 * Top-level migration statements that must not run inside migrate.js harness transactions.
 * (Runner owns BEGIN/COMMIT for --execute and --dry-run-all.)
 */
function isSkippableTransactionControlStatement(sql) {
  const t = String(sql || '')
    .trim()
    .replace(/;+\s*$/u, '')
    .toUpperCase();
  if (!t) return true;
  if (t === 'BEGIN' || t === 'COMMIT' || t === 'ROLLBACK' || t === 'END') return true;
  if (t === 'BEGIN TRANSACTION' || t === 'COMMIT TRANSACTION' || t === 'ROLLBACK TRANSACTION') {
    return true;
  }
  if (/^SAVEPOINT\s+\S+$/.test(t)) return true;
  if (/^RELEASE\s+SAVEPOINT\s+\S+$/.test(t)) return true;
  if (/^ROLLBACK\s+TO\s+SAVEPOINT\s+\S+$/.test(t)) return true;
  return false;
}

module.exports = {
  isSkippableTransactionControlStatement,
};