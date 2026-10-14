'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');

const {
  parseCliArgs,
  isStatusMismatch,
  auditFirestoreDeadLetters,
} = require('../../scripts/check_sync_parity');

test('Parity Auditor: parseCliArgs parses --audit by default or when specified', () => {
  // Default when no args
  const defaultFlags = parseCliArgs([]);
  assert.equal(defaultFlags.isAudit, true);
  assert.equal(defaultFlags.prefix, '');
  assert.equal(defaultFlags.errors.length, 0);

  // Explicit --audit
  const explicitFlags = parseCliArgs(['--audit']);
  assert.equal(explicitFlags.isAudit, true);
  assert.equal(explicitFlags.errors.length, 0);
});

test('Parity Auditor: parseCliArgs parses --collection-prefix with and without quotes and spaces', () => {
  // Form 1: --collection-prefix="staging_"
  const flags1 = parseCliArgs(['--audit', '--collection-prefix="staging_"']);
  assert.equal(flags1.prefix, 'staging_');

  // Form 2: --collection-prefix='staging_'
  const flags2 = parseCliArgs(['--audit', "--collection-prefix='staging_'"]);
  assert.equal(flags2.prefix, 'staging_');

  // Form 3: --collection-prefix prefix_
  const flags3 = parseCliArgs(['--audit', '--collection-prefix', 'prefix_']);
  assert.equal(flags3.prefix, 'prefix_');
});

test('Parity Auditor: parseCliArgs handles --help and rejects unknown/write options like --reconcile', () => {
  const helpFlags = parseCliArgs(['--help']);
  assert.equal(helpFlags.isHelp, true);

  const shortHelpFlags = parseCliArgs(['-h']);
  assert.equal(shortHelpFlags.isHelp, true);

  // --reconcile is rejected as unknown (read-only audit tool)
  const unknownFlags = parseCliArgs(['--audit', '--reconcile']);
  assert.equal(unknownFlags.errors.length, 1);
  assert.ok(unknownFlags.errors[0].includes('Unknown option: --reconcile'));
});

test('Parity Auditor: isStatusMismatch compares effective status correctly', () => {
  // 1. Identical active status matches
  assert.equal(
    isStatusMismatch(
      { doctor_status: 'confirmed', patient_status: 'confirmed' },
      { doctorStatus: 'confirmed', patientStatus: 'confirmed' }
    ),
    false
  );

  // 2. Doctor status divergence is always a mismatch
  assert.equal(
    isStatusMismatch(
      { doctor_status: 'inProgress', patient_status: 'confirmed' },
      { doctorStatus: 'confirmed', patientStatus: 'confirmed' }
    ),
    true
  );

  // 3. PostgreSQL patient_status cancelled is effective match if Firestore doctorStatus is cancelled
  // (Intentional non-propagation of terminal patient_status to Firestore)
  assert.equal(
    isStatusMismatch(
      { doctor_status: 'cancelled', patient_status: 'cancelled' },
      { doctorStatus: 'cancelled', patientStatus: 'pending' }
    ),
    false
  );

  // 4. PostgreSQL patient_status completed is effective match if Firestore doctorStatus is completed
  assert.equal(
    isStatusMismatch(
      { doctor_status: 'completed', patient_status: 'completed' },
      { doctorStatus: 'completed', patientStatus: 'confirmed' }
    ),
    false
  );

  // 5. Active patient_status mismatch is flagged
  assert.equal(
    isStatusMismatch(
      { doctor_status: 'confirmed', patient_status: 'confirmed' },
      { doctorStatus: 'confirmed', patientStatus: 'pending' }
    ),
    true
  );
});

test('Parity Auditor: auditFirestoreDeadLetters aggregates dead letter counts by reason (read-only)', async () => {
  const mockDocs = [
    { id: 'dl-1', data: () => ({ reason: 'terminal_state' }) },
    { id: 'dl-2', data: () => ({ reason: 'firestore_doc_missing' }) },
    { id: 'dl-3', data: () => ({ reason: 'terminal_state' }) },
    { id: 'dl-4', data: () => ({ reason: 'invalid_argument' }) },
  ];

  const mockFirestore = {
    collection: (colName) => {
      assert.equal(colName, 'staging_syncDeadLetters');
      return {
        get: async () => ({
          size: mockDocs.length,
          docs: mockDocs,
        }),
      };
    },
  };

  const result = await auditFirestoreDeadLetters(mockFirestore, { prefix: 'staging_' });
  assert.equal(result.total, 4);
  assert.deepEqual(result.reasonCounts, {
    terminal_state: 2,
    firestore_doc_missing: 1,
    invalid_argument: 1,
  });
});

