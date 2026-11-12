import { it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { DOCUMENT_AUDIENCE_ALL_SQL, ensureDocumentAudienceSchema } from '../src/modules/document_audience_schema.js';

it('audience upgrade is additive and migration matches runtime SQL without changing documents', () => {
  const migration = fs.readFileSync(new URL('../migrations/131_document_everyone_audience.sql', import.meta.url), 'utf8');
  assert.equal(migration.slice(migration.indexOf('DO $$')).trim(), DOCUMENT_AUDIENCE_ALL_SQL.trim());
  assert.match(migration, /CHECK \(audience IN \('residents', 'board', 'managers', 'all'\)\)/);
  assert.doesNotMatch(migration, /\b(?:UPDATE|INSERT|DELETE)\b/i);
});

it('validated all constraint makes runtime ensure read-only', async () => {
  const calls = [];
  await ensureDocumentAudienceSchema({ query: async (sql) => {
    calls.push(sql);
    return { rows: [{ ready: true }] };
  } });
  assert.equal(calls.length, 1);
  assert.ok(calls[0].startsWith('SELECT EXISTS'));
});

it('older constraint runs the guarded upgrade once and surfaces failure', async () => {
  const calls = [];
  await ensureDocumentAudienceSchema({ query: async (sql) => {
    calls.push(sql);
    return { rows: [{ ready: false }] };
  } });
  assert.equal(calls.length, 2);
  assert.equal(calls[1], DOCUMENT_AUDIENCE_ALL_SQL);
  await assert.rejects(ensureDocumentAudienceSchema({ query: async () => {
    throw new Error('database unavailable');
  } }), /database unavailable/);
});
