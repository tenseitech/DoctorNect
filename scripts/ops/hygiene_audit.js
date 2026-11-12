'use strict';

/**
 * scripts/ops/hygiene_audit.js
 * 
 * Round 10 Item 7: Hygiene and PII / Secrets Audit
 * Scans all tracked git files for:
 * 1. Forbidden staging project refs (see infra_url_policy.FORBIDDEN_SUPABASE_REFS)
 * 2. Pooler hostnames ('pooler.supabase.com')
 * 3. Phone numbers (e.g. +91XXXXXXXXXX)
 * 
 * Reports counts and file paths only. Never prints secrets or credentials.
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function getTrackedFiles() {
  const output = execSync('git ls-files', { encoding: 'utf8' });
  return output.split(/\r?\n/).filter(f => f.trim().length > 0 && fs.existsSync(f));
}

function runAudit() {
  console.log('================================================================');
  console.log('DOCTORNECT: TRACKED FILES HYGIENE & SECRETS AUDIT');
  console.log('Timestamp: ' + new Date().toISOString());
  console.log('================================================================\n');

  const files = getTrackedFiles();
  console.log(`Total Tracked Files in Git: ${files.length}\n`);

  const { FORBIDDEN_SUPABASE_REFS } = require('../lib/infra_url_policy');
  const POOLER_HOST = 'pooler.supabase.com';
  const PHONE_REGEX = /(\+91[6-9]\d{9}|[6-9]\d{9})/g;

  const matchesRef = [];
  const matchesPooler = [];
  const matchesPhone = [];

  for (const file of files) {
    // Skip binary files and git metadata
    if (file.endsWith('.png') || file.endsWith('.jpg') || file.endsWith('.ico') || file.endsWith('.zip') || file.endsWith('.exe')) {
      continue;
    }

    let content;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch (_) {
      continue;
    }

    for (const ref of FORBIDDEN_SUPABASE_REFS) {
      if (content.includes(ref)) {
        const occurrences = (content.match(new RegExp(ref, 'g')) || []).length;
        matchesRef.push({ file, ref, occurrences });
      }
    }

    if (content.includes(POOLER_HOST)) {
      const occurrences = (content.match(new RegExp(POOLER_HOST, 'g')) || []).length;
      matchesPooler.push({ file, occurrences });
    }

    const phoneMatches = content.match(PHONE_REGEX);
    if (phoneMatches && phoneMatches.length > 0) {
      // Exclude documentation or code examples if purely test/sample
      matchesPhone.push({ file, occurrences: phoneMatches.length });
    }
  }

  console.log('----------------------------------------------------------------');
  console.log('1. FORBIDDEN SUPABASE PROJECT REF AUDIT');
  console.log('----------------------------------------------------------------');
  console.log(`Total Tracked Files Matching: ${matchesRef.length}`);
  for (const m of matchesRef) {
    console.log(`  - [${m.occurrences} matches] ${m.file}`);
  }
  console.log();

  console.log('----------------------------------------------------------------');
  console.log('2. SUPABASE POOLER HOSTNAME AUDIT (' + POOLER_HOST + ')');
  console.log('----------------------------------------------------------------');
  console.log(`Total Tracked Files Matching: ${matchesPooler.length}`);
  for (const m of matchesPooler) {
    console.log(`  - [${m.occurrences} matches] ${m.file}`);
  }
  console.log();

  console.log('----------------------------------------------------------------');
  console.log('3. PHONE NUMBER PATTERN AUDIT (+91 / 10-digit Indian Mobiles)');
  console.log('----------------------------------------------------------------');
  console.log(`Total Tracked Files Matching: ${matchesPhone.length}`);
  for (const m of matchesPhone) {
    console.log(`  - [${m.occurrences} occurrences] ${m.file}`);
  }
  console.log();

  console.log('================================================================');
  console.log('HYGIENE AUDIT COMPLETED.');
  console.log('================================================================\n');
}

runAudit();

