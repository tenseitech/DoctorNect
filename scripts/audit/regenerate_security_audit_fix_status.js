#!/usr/bin/env node
'use strict';

/**
 * Regenerate SECURITY_AUDIT §9 Fix status from §2 findings table (1 row per SEC-xxx, no ranges).
 * Usage: node scripts/audit/regenerate_security_audit_fix_status.js [--check]
 */

const fs = require('fs');
const path = require('path');

const AUDIT_PATH = path.join(__dirname, '../../docs/audit/SECURITY_AUDIT_2026-11-23.md');
const SECTION_START = '## 9. Fix status (Part F';
const SECTION_END = '*Report generated read-only';

function parseFindingsTable(markdown) {
  const lines = markdown.split(/\r?\n/);
  const rows = [];
  for (const line of lines) {
    if (!line.startsWith('| SEC-')) continue;
    const cells = line.split('|').map((c) => c.trim()).filter(Boolean);
    if (cells.length < 6) continue;
    const [id, severity, area, title, location, fixSummary, effort] = cells;
    if (!/^SEC-\d{3}$/.test(id)) continue;
    rows.push({ id, severity, area, title, location, fixSummary, effort: effort || '—' });
  }
  return rows;
}

function statusForRow({ id, fixSummary, effort, title }) {
  const fix = fixSummary || '';
  if (/Part B approved/i.test(fix)) {
    return 'Done (committed, not deployed)';
  }
  if (/Deferred|deferred/i.test(fix) || id === 'SEC-021' && /Part C/i.test(fix)) {
    return 'Open — FORCE RLS deferred (Phase 2; staging harness)';
  }
  if (/docs only|Design only/i.test(fix)) {
    return 'Design / docs only';
  }
  if (/Verified 2026|^\*\*Verified/i.test(fix) || (effort === '—' && /No change/i.test(fix))) {
    return 'Verified';
  }
  if (/Keep\b|Maintain/i.test(fix)) {
    return 'Maintain';
  }
  if (/Catalog:.*0.*definer/i.test(fix) && id === 'SEC-021') {
    return 'Partial — catalog done; FORCE migration deferred (PC-01)';
  }
  if (/runbook|disable after Play/i.test(title + fix) && id === 'SEC-009') {
    return 'Open (ops) — runbook in docs/ops/REVIEWER_OTP_DISABLE.md';
  }
  if (/MSG91|billing|dashboard cap/i.test(fix) && id === 'SEC-017') {
    return 'Open — Part D design in docs/ops/MSG91_SMS_BUDGET_DESIGN.md';
  }
  return 'Open';
}

function notesFromFix(fixSummary) {
  const s = String(fixSummary || '').replace(/\*\*/g, '');
  return s.length > 120 ? `${s.slice(0, 117)}…` : s;
}

function buildSection9(findings) {
  const header = `## 9. Fix status (Part F — auto-generated from §2)

| ID | Severity | Status | Notes (from §2 fix summary) |
|----|----------|--------|---------------------------|
| **PC-01** | Medium | **Deferred (Phase 2)** | \`20261123101500\` in \`db/migrations/deferred/\` — apply after staging \`rls_sql_harness\` pass |
| **Part D — SEC-009** | High | **Docs only** | [REVIEWER_OTP_DISABLE.md](../ops/REVIEWER_OTP_DISABLE.md) |
| **Part D — SEC-017** | Medium | **Design only** | [MSG91_SMS_BUDGET_DESIGN.md](../ops/MSG91_SMS_BUDGET_DESIGN.md) |`;

  const body = findings
    .map((row) => {
      const status = statusForRow(row);
      const notes = notesFromFix(row.fixSummary);
      return `| ${row.id} | ${row.severity} | ${status} | ${notes} |`;
    })
    .join('\n');

  return `${header}\n${body}\n\n---\n\n`;
}

function replaceSection9(markdown, newSection) {
  const startIdx = markdown.indexOf(SECTION_START);
  const endIdx = markdown.indexOf(SECTION_END, startIdx);
  if (startIdx === -1 || endIdx === -1) {
    throw new Error('Could not find §9 boundaries in SECURITY_AUDIT markdown');
  }
  return markdown.slice(0, startIdx) + newSection + markdown.slice(endIdx);
}

function main() {
  const checkOnly = process.argv.includes('--check');
  const md = fs.readFileSync(AUDIT_PATH, 'utf8');
  const findings = parseFindingsTable(md);
  if (findings.length !== 40) {
    throw new Error(`Expected 40 SEC rows in §2, got ${findings.length}`);
  }
  const section = buildSection9(findings);
  const out = replaceSection9(md, section);
  if (checkOnly) {
    process.stdout.write(section);
    return;
  }
  fs.writeFileSync(AUDIT_PATH, out, 'utf8');
  console.log(`Updated §9 with ${findings.length} SEC rows + PC-01 + Part D rows.`);
}

main();