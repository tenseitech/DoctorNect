'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  deleteS3PrefixVersions,
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

test('resolveUserS3Prefixes: lab deletion deletes lab report prefix but NEVER touches health_records', async () => {
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

  // Lab's own report prefix is targeted
  assert.ok(labPrefixes.includes('lab_reports/lab_profile_123/'), 'Must include lab own report prefix');
  assert.ok(labPrefixes.includes('labs/lab_profile_123/'), 'Must include labs profile prefix');
  assert.ok(labPrefixes.includes('promoted_ads/lab_uid_123/'), 'Must include promoted ads prefix');

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
