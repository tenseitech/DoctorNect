'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  deleteS3PrefixVersions,
  deleteS3SpecificKeysVersions,
  collectRoleSpecificS3ReportKeys,
  resolveUserS3Prefixes,
  cleanupUserS3Prefixes,
  setS3ClientForTesting,
} = require('../delete_my_account');
const {
  ListObjectVersionsCommand,
  DeleteObjectsCommand,
} = require('@aws-sdk/client-s3');

test('deleteS3PrefixVersions: targets ALL versions and delete markers across pages in batches', async () => {
  const sentCommands = [];
  let listCallCount = 0;

  const mockS3 = {
    send: async (cmd) => {
      sentCommands.push(cmd);
      if (cmd instanceof ListObjectVersionsCommand) {
        listCallCount++;
        if (listCallCount === 1) {
          // Page 1: truncated, has versions and delete markers
          return {
            IsTruncated: true,
            NextKeyMarker: 'key_page_2',
            NextVersionIdMarker: 'ver_page_2',
            Versions: [
              { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'v1_original' },
              { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'v2_updated' },
            ],
            DeleteMarkers: [
              { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'dm_marker_1' },
            ],
          };
        } else {
          // Page 2: final page
          return {
            IsTruncated: false,
            Versions: [
              { Key: 'patients/p_1/profile/pic2.jpg', VersionId: 'v3_other' },
            ],
            DeleteMarkers: [],
          };
        }
      }

      if (cmd instanceof DeleteObjectsCommand) {
        return { Deleted: cmd.input.Delete.Objects };
      }

      return {};
    },
  };

  const result = await deleteS3PrefixVersions(mockS3, 'test-bucket', 'patients/p_1/');

  assert.equal(result.success, true);
  assert.equal(result.count, 4); // 3 on page 1 + 1 on page 2

  // Verify ListObjectVersions calls
  const listCommands = sentCommands.filter((c) => c instanceof ListObjectVersionsCommand);
  assert.equal(listCommands.length, 2);
  assert.equal(listCommands[0].input.Prefix, 'patients/p_1/');
  assert.equal(listCommands[1].input.KeyMarker, 'key_page_2');

  // Verify DeleteObjects calls
  const deleteCommands = sentCommands.filter((c) => c instanceof DeleteObjectsCommand);
  assert.equal(deleteCommands.length, 2);

  const deletedObjects = deleteCommands.flatMap((c) => c.input.Delete.Objects);
  assert.deepEqual(deletedObjects, [
    { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'v1_original' },
    { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'v2_updated' },
    { Key: 'patients/p_1/profile/pic.jpg', VersionId: 'dm_marker_1' },
    { Key: 'patients/p_1/profile/pic2.jpg', VersionId: 'v3_other' },
  ]);
});

test('deleteS3SpecificKeysVersions: deletes all versions of exact keys without touching prefix collisions', async () => {
  const sentCommands = [];

  const mockS3 = {
    send: async (cmd) => {
      sentCommands.push(cmd);
      if (cmd instanceof ListObjectVersionsCommand) {
        if (cmd.input.Prefix === 'lab_reports/pat_1/book_1/report.pdf') {
          return {
            IsTruncated: false,
            Versions: [
              { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'v1' },
              { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'v2' },
              // Prefix collision that does NOT exactly match should be ignored
              { Key: 'lab_reports/pat_1/book_1/report.pdf.bak', VersionId: 'v_other' },
            ],
            DeleteMarkers: [
              { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'dm1' },
            ],
          };
        }
        if (cmd.input.Prefix === 'lab_reports/pat_2/order_1/report.pdf') {
          return {
            IsTruncated: false,
            Versions: [
              { Key: 'lab_reports/pat_2/order_1/report.pdf', VersionId: 'v_order1' },
            ],
            DeleteMarkers: [],
          };
        }
      }

      if (cmd instanceof DeleteObjectsCommand) {
        return { Deleted: cmd.input.Delete.Objects };
      }
      return {};
    },
  };

  const keys = [
    'lab_reports/pat_1/book_1/report.pdf',
    'lab_reports/pat_2/order_1/report.pdf',
  ];

  const result = await deleteS3SpecificKeysVersions(mockS3, 'test-bucket', keys);
  assert.equal(result.success, true);
  assert.equal(result.count, 4); // 2 versions + 1 delete marker for book_1, 1 version for order_1

  const deleteCmd = sentCommands.find((c) => c instanceof DeleteObjectsCommand);
  assert.ok(deleteCmd, 'Must send DeleteObjectsCommand');

  const deletedObjects = deleteCmd.input.Delete.Objects;
  assert.deepEqual(deletedObjects, [
    { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'v1' },
    { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'v2' },
    { Key: 'lab_reports/pat_1/book_1/report.pdf', VersionId: 'dm1' },
    { Key: 'lab_reports/pat_2/order_1/report.pdf', VersionId: 'v_order1' },
  ]);

  // Ensure prefix collision was NOT included
  const collisionFound = deletedObjects.some((o) => o.Key.endsWith('.bak'));
  assert.equal(collisionFound, false, 'Must not delete prefix collision keys');
});

test('collectRoleSpecificS3ReportKeys: queries lab_bookings and lab_orders for labId and collects reportStorageKey', async () => {
  const bookingsData = [
    { id: 'b1', labId: 'lab_target', reportStorageKey: 'lab_reports/pat_A/b1/uuid-a.pdf', reportStorageProvider: 's3' },
    { id: 'b2', labId: 'lab_target', reportStorageKey: 'lab_reports/pat_B/b2/uuid-b.pdf', reportStorageProvider: 's3' },
    { id: 'b3', labId: 'lab_OTHER', reportStorageKey: 'lab_reports/pat_C/b3/uuid-c.pdf', reportStorageProvider: 's3' },
    { id: 'b4', labId: 'lab_target', reportStorageKey: 'legacy_url_no_s3', reportStorageProvider: 'firebase' },
  ];

  const ordersData = [
    { id: 'o1', labId: 'lab_target', reportStorageKey: 'lab_reports/pat_D/o1/uuid-d.pdf', reportStorageProvider: 's3' },
    { id: 'o2', labId: 'lab_OTHER', reportStorageKey: 'lab_reports/pat_E/o2/uuid-e.pdf', reportStorageProvider: 's3' },
  ];

  const mockDb = {
    collection: (col) => ({
      where: (field, op, val) => ({
        get: async () => {
          if (col === 'lab_bookings' && field === 'labId') {
            const matches = bookingsData.filter((b) => b.labId === val);
            return { docs: matches.map((m) => ({ id: m.id, data: () => m })) };
          }
          if (col === 'lab_orders' && field === 'labId') {
            const matches = ordersData.filter((o) => o.labId === val);
            return { docs: matches.map((m) => ({ id: m.id, data: () => m })) };
          }
          return { docs: [] };
        },
      }),
    }),
  };

  const collected = await collectRoleSpecificS3ReportKeys(mockDb, {
    role: 'lab',
    profileId: 'lab_target',
    uid: 'lab_user_uid',
  });

  // Must collect only target lab's s3 reportStorageKey values
  assert.equal(collected.length, 3);
  assert.ok(collected.includes('lab_reports/pat_A/b1/uuid-a.pdf'));
  assert.ok(collected.includes('lab_reports/pat_B/b2/uuid-b.pdf'));
  assert.ok(collected.includes('lab_reports/pat_D/o1/uuid-d.pdf'));

  // Must NEVER collect reports belonging to other labs
  assert.equal(collected.includes('lab_reports/pat_C/b3/uuid-c.pdf'), false);
  assert.equal(collected.includes('lab_reports/pat_E/o2/uuid-e.pdf'), false);
});

test('resolveUserS3Prefixes: lab deletion deletes labs profile prefix and promoted ads prefix, but does NOT include lab_reports prefix', async () => {
  const mockDb = {
    collection: () => ({
      where: () => ({
        get: async () => ({ docs: [] }),
      }),
    }),
  };

  const labPrefixes = await resolveUserS3Prefixes(mockDb, {
    uid: 'lab_uid_123',
    role: 'lab',
    profileId: 'lab_profile_123',
  });

  // Lab profile and promoted ads prefixes are targeted
  assert.ok(labPrefixes.includes('labs/lab_profile_123/'), 'Must include labs profile prefix');
  assert.ok(labPrefixes.includes('promoted_ads/lab_uid_123/'), 'Must include promoted ads prefix');

  // Crucial: lab_reports prefix must NOT be in prefix list (no lab_reports/{labId}/ exists!)
  const touchesLabReports = labPrefixes.some((p) => p.startsWith('lab_reports/'));
  assert.equal(touchesLabReports, false, 'Lab deletion must NOT include lab_reports prefix');

  // Crucial: patient health_records prefix must NOT be touched
  const touchesHealthRecords = labPrefixes.some((p) => p.startsWith('health_records/'));
  assert.equal(touchesHealthRecords, false, 'Lab deletion must NOT touch health_records prefix');

  // Crucial: other patients prefixes must NOT be touched
  const touchesOtherPatient = labPrefixes.some((p) => p.startsWith('patients/'));
  assert.equal(touchesOtherPatient, false, 'Lab deletion must NOT touch patients prefix');
});

test('resolveUserS3Prefixes: patient deletion deletes patient photos, health records, and own lab reports', async () => {
  const mockDb = {
    collection: () => ({
      where: () => ({
        get: async () => ({ docs: [] }),
      }),
    }),
  };

  const patientPrefixes = await resolveUserS3Prefixes(mockDb, {
    uid: 'patient_uid_456',
    role: 'patient',
    profileId: 'p_456',
  });

  assert.ok(patientPrefixes.includes('patients/p_456/'), 'Must include patients prefix');
  assert.ok(patientPrefixes.includes('health_records/p_456/'), 'Must include patient health records prefix');
  assert.ok(patientPrefixes.includes('lab_reports/p_456/'), 'Must include patient own lab reports prefix');
  assert.ok(patientPrefixes.includes('promoted_ads/patient_uid_456/'), 'Must include promoted ads prefix');
});

test('cleanupUserS3Prefixes: failure in one prefix soft-fails and does not stop other prefixes', async () => {
  const attemptedPrefixes = [];

  const mockS3 = {
    send: async (cmd) => {
      if (cmd instanceof ListObjectVersionsCommand) {
        attemptedPrefixes.push(cmd.input.Prefix);
        if (cmd.input.Prefix === 'failing_prefix/doc_1/') {
          throw new Error('S3 access denied on failing prefix');
        }
        return {
          IsTruncated: false,
          Versions: [{ Key: `${cmd.input.Prefix}test.jpg`, VersionId: 'v1' }],
        };
      }
      return {};
    },
  };

  const prefixes = [
    'patients/p_1/',
    'failing_prefix/doc_1/',
    'health_records/p_1/',
  ];

  const failedPrefixes = await cleanupUserS3Prefixes(mockS3, 'test-bucket', prefixes);

  // All 3 prefixes must have been attempted despite failure on 2nd
  assert.deepEqual(attemptedPrefixes, [
    'patients/p_1/',
    'failing_prefix/doc_1/',
    'health_records/p_1/',
  ]);

  // Only the failing prefix is reported
  assert.deepEqual(failedPrefixes, ['failing_prefix/doc_1/']);
});

test('deleteS3SpecificKeysVersions: failure in one key soft-fails and continues with others', async () => {
  const attemptedKeys = [];

  const mockS3 = {
    send: async (cmd) => {
      if (cmd instanceof ListObjectVersionsCommand) {
        attemptedKeys.push(cmd.input.Prefix);
        if (cmd.input.Prefix === 'failing_report_key.pdf') {
          throw new Error('S3 500 error on listing');
        }
        return {
          IsTruncated: false,
          Versions: [{ Key: cmd.input.Prefix, VersionId: 'v1' }],
        };
      }
      if (cmd instanceof DeleteObjectsCommand) {
        return { Deleted: cmd.input.Delete.Objects };
      }
      return {};
    },
  };

  const keys = ['good_report_1.pdf', 'failing_report_key.pdf', 'good_report_2.pdf'];
  const res = await deleteS3SpecificKeysVersions(mockS3, 'test-bucket', keys);

  assert.equal(res.success, false);
  assert.deepEqual(res.failedKeys, ['failing_report_key.pdf']);
  assert.equal(res.count, 2); // 2 successful deletions
  assert.deepEqual(attemptedKeys, ['good_report_1.pdf', 'failing_report_key.pdf', 'good_report_2.pdf']);
});
