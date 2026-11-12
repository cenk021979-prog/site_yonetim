import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolvePeopleAccess } from './people_access.js';
import { listAlarmSites } from './emergency_alarm_access.js';
import { createEmergencyAlarm, listAlarmElevators, listAlarmLocations, listEmergencyAlarms, listEmergencyAlarmHistory, markEmergencyAlarm } from './emergency_alarm_service.js';
import { getAlarmResponders, saveAlarmResponders } from './emergency_alarm_recipients.js';

export const emergencyAlarmRouter = express.Router();
export const emergencyAlarmReadLimiter = createRuleLimiter({ rules: [{ windowMs: HOUR_MS, max: 3600, key: userKey }, { windowMs: HOUR_MS, max: 36000, key: ipKey }], message: 'Çok fazla alarm sorgusu. Biraz sonra deneyin.', includeRetryBody: true });
export const emergencyAlarmWriteLimiter = createRuleLimiter({ rules: [{ windowMs: HOUR_MS, max: 2400, key: userKey }, { windowMs: HOUR_MS, max: 24000, key: ipKey }], message: 'Çok fazla alarm işlemi. Biraz sonra deneyin.', includeRetryBody: true });
const handle = (job) => async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  try { const body = await job(req, res); if (body !== undefined) res.json(body); }
  catch (error) { respondError(res, 'emergency_alarm', error, 'Acil alarm işlemi tamamlanamadı.'); }
};
emergencyAlarmRouter.get('/app/emergency/sites', authRequired, emergencyAlarmReadLimiter, handle((req) => listAlarmSites(req.authUser)));
emergencyAlarmRouter.get('/app/emergency/sites/:siteCode/elevators', authRequired, emergencyAlarmReadLimiter, handle((req) => listAlarmElevators({ authUser: req.authUser, siteCode: req.params.siteCode })));
emergencyAlarmRouter.get('/app/emergency/sites/:siteCode/locations', authRequired, emergencyAlarmReadLimiter, handle((req) => listAlarmLocations({ authUser: req.authUser, siteCode: req.params.siteCode })));
emergencyAlarmRouter.get('/app/emergency/alarms', authRequired, emergencyAlarmReadLimiter, handle((req) => listEmergencyAlarms(req.authUser)));
emergencyAlarmRouter.get('/app/emergency/alarms/history', authRequired, emergencyAlarmReadLimiter, handle((req) => listEmergencyAlarmHistory({ authUser: req.authUser, beforeId: req.query.before_id })));
emergencyAlarmRouter.post('/app/emergency/alarms', authRequired, emergencyAlarmWriteLimiter, handle((req) => createEmergencyAlarm({ authUser: req.authUser, body: req.body })));
for (const action of ['received', 'played', 'ack', 'resolve']) emergencyAlarmRouter.post(`/app/emergency/alarms/:id/${action}`, authRequired, emergencyAlarmWriteLimiter, handle((req) => markEmergencyAlarm({ authUser: req.authUser, rawId: req.params.id, action })));
emergencyAlarmRouter.get('/manager/sites/:siteCode/emergency/responders', authRequired, emergencyAlarmReadLimiter, handle(async (req, res) => {
  const access = await resolvePeopleAccess(req, res, { write: true });
  if (access) return getAlarmResponders(access.siteCode);
}));
emergencyAlarmRouter.put('/manager/sites/:siteCode/emergency/responders', authRequired, emergencyAlarmWriteLimiter, handle(async (req, res) => {
  const access = await resolvePeopleAccess(req, res, { write: true });
  if (access) return saveAlarmResponders({ siteCode: access.siteCode, body: req.body, actor: req.authUser });
}));
