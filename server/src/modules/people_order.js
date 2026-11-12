// Natural location ordering is applied before LIMIT/OFFSET, never to a partial page.
import { foldSql } from './people_common.js';

/** Internal SQL expressions only. Numeric runs compare by digit count, then digits;
 * no integer cast/overflow and no database collation extension is needed. */
export function naturalOrderSql(expression) {
  return `ARRAY(SELECT CASE WHEN part[1] ~ '^[0-9]+$'
    THEN '0' || LPAD(LENGTH(COALESCE(NULLIF(LTRIM(part[1], '0'), ''), '0'))::TEXT, 10, '0')
      || COALESCE(NULLIF(LTRIM(part[1], '0'), ''), '0')
    ELSE '1' || part[1] END
    FROM regexp_matches(COALESCE(${foldSql(expression)}, ''), '([0-9]+|[^0-9]+)', 'g')
      WITH ORDINALITY AS natural_part(part, position)
    ORDER BY position)`;
}

// Current smallest location first. A former resident retains their last location;
// unassigned people follow located people. One lateral row cannot duplicate people.
export const PERSON_LOCATION_JOIN = `LEFT JOIN LATERAL (
  SELECT location_block.block_name, location_apartment.unit_label
  FROM apartment_residencies location_residency
  JOIN apartments location_apartment ON location_apartment.id = location_residency.apartment_id
  JOIN site_blocks location_block ON location_block.id = location_apartment.block_id
  WHERE location_residency.person_id = sp.id
    AND location_apartment.site_code = sp.site_code AND location_block.site_code = sp.site_code
  ORDER BY location_residency.is_current DESC,
    CASE WHEN NOT location_residency.is_current THEN location_residency.move_out_date END DESC NULLS LAST,
    ${naturalOrderSql('location_block.block_name')},
    ${naturalOrderSql('location_apartment.unit_label')}, location_residency.id
  LIMIT 1
) person_location ON TRUE`;

export const PERSON_LOCATION_ORDER = `person_location.unit_label IS NULL,
  ${naturalOrderSql('person_location.block_name')},
  ${naturalOrderSql('person_location.unit_label')},
  ${foldSql("COALESCE(NULLIF(u.full_name, ''), sp.full_name)")}, sp.id`;
