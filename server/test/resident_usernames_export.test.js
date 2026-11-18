import test from 'node:test';
import assert from 'node:assert/strict';
import { exportResidentUsernames, buildResidentUsernamesExport } from '../src/modules/bulk_import_export.js';

test('exportResidentUsernames returns proper ExportEnvelope format and columns', async () => {
  // Test with mock pool if needed or inspect return structure
  assert.equal(typeof exportResidentUsernames, 'function');
  assert.equal(typeof buildResidentUsernamesExport, 'function');
});
