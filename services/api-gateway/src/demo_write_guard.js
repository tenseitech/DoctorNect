'use strict';

const { DEMO_ACCOUNTS } = require('../../../scripts/lib/demo_accounts');

const DEMO_DIGITS = new Set(DEMO_ACCOUNTS.map((a) => a.digits));

/** True when one JSON value is a phone number that ends in one of the five demo numbers. */
function valueIsDemoMobile(value) {
  if (typeof value !== 'string' && typeof value !== 'number') return false;
  const digits = String(value).replace(/\D/g, '');
  if (digits.length < 10 || digits.length > 13) return false;
  return DEMO_DIGITS.has(digits.slice(-10));
}

function walk(node, depth = 0) {
  if (depth > 20 || node === null || node === undefined) return false;
  if (Array.isArray(node)) return node.some((v) => walk(v, depth + 1));
  if (typeof node === 'object') return Object.values(node).some((v) => walk(v, depth + 1));
  return valueIsDemoMobile(node);
}

/**
 * Production RDS writes must never store one of the reserved demo numbers (demo accounts live
 * only on the staging plane). Applied to client writes routed to RDS (POST/PATCH/PUT).
 * @param {Buffer|string} body raw request body
 * @returns {boolean} true when the write must be refused
 */
function writeContainsDemoMobile(body) {
  const text = Buffer.isBuffer(body) ? body.toString('utf8') : String(body || '');
  if (!text.trim()) return false;
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    return false;
  }
  return walk(parsed);
}

module.exports = { writeContainsDemoMobile, valueIsDemoMobile };
