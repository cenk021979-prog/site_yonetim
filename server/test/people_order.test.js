import { it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PERSON_LOCATION_JOIN, PERSON_LOCATION_ORDER, naturalOrderSql } from '../src/modules/people_order.js';

it('location selection is single-row, site scoped, current-first and uses no integer casts', () => {
  assert.match(PERSON_LOCATION_JOIN, /location_apartment\.site_code = sp\.site_code/);
  assert.match(PERSON_LOCATION_JOIN, /is_current DESC/);
  assert.match(PERSON_LOCATION_JOIN, /LIMIT 1/);
  assert.match(PERSON_LOCATION_ORDER, /unit_label IS NULL/);
  assert.doesNotMatch(naturalOrderSql('unit_label'), /::(?:INTEGER|BIGINT|NUMERIC)/i);
});
it('people pagination orders the complete database result before LIMIT, and export uses the same ordering', () => {
  for (const name of ['people_service.js', 'bulk_import_export.js']) {
    const source = readFileSync(new URL(`../src/modules/${name}`, import.meta.url), 'utf8');
    assert.match(source, /\$\{PERSON_LOCATION_JOIN\}[\s\S]*?ORDER BY \$\{PERSON_LOCATION_ORDER\}[\s\S]*?LIMIT/);
  }
});
