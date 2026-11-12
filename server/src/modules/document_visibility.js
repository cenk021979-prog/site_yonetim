// Explicit whole-site sharing. Legacy residents/managers rules are never broadened.
import { PlatformError } from './errors.js';

export const PUBLIC_DOCUMENT_AUDIENCES = Object.freeze(['residents', 'all']);
export const isPublicDocumentAudience = (value) => PUBLIC_DOCUMENT_AUDIENCES.includes(value);

/** Old clients parse all as unknown and silently PATCH managers even on metadata edits. */
export function assertSupportedDocumentAudienceChange(currentAudience, requestedAudience) {
  if (currentAudience === 'all' && requestedAudience === 'managers') {
    throw new PlatformError(
      409,
      'DOCUMENT_AUDIENCE_UNSUPPORTED',
      'Bu belgenin paylaşımını değiştirmek için uygulamayı güncelleyin veya güncel web sürümünde Herkes ya da Yönetim seçin.',
    );
  }
}

/** Trusted SQL aliases/parameters only; callers provide the existing my_apts CTE. */
export function allDocumentSiteAccessSql(d = 'd', user = '$1') {
  return `(
    EXISTS (SELECT 1 FROM users document_user WHERE document_user.user_code = ${user} AND document_user.is_active = TRUE)
    AND EXISTS (SELECT 1 FROM sites document_site WHERE document_site.site_code = ${d}.site_code AND document_site.approval_status = 'approved')
    AND ${d}.site_code IN (
      SELECT m.site_code FROM my_apts m
      UNION SELECT sms.site_code FROM site_manager_sites sms WHERE sms.manager_user_code = ${user}
      UNION SELECT sm.site_code FROM site_memberships sm
        WHERE sm.user_code = ${user} AND sm.is_active = TRUE
          AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER', 'STAFF')
    )
  )`;
}

export function publicDocumentAccessSql(d, user, legacyAccessSql) {
  return `((${d}.audience = 'all' AND ${allDocumentSiteAccessSql(d, user)})
    OR (${d}.audience = 'residents' AND ${legacyAccessSql}))`;
}
