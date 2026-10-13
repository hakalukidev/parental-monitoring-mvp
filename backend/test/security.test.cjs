const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const request = require('supertest');
const { io: client } = require('socket.io-client');
const { Server } = require('socket.io');

Object.assign(process.env, { NODE_ENV: 'test', MONGO_URI: 'mongodb://127.0.0.1/seftly_isolated_test', JWT_ACCESS_SECRET: 'test-access-secret-only-not-a-live-credential', JWT_REFRESH_SECRET: 'test-refresh-secret-only-not-a-live-credential', SESSION_TOKEN_SECRET: 'test-session-secret-only-not-a-live-credential', PARENT_CHILD_API_TOKEN: 'isolated-service-token', CORS_ORIGINS: 'http://localhost', TRUST_PROXY_HOPS: '0' });
const { createApp } = require('../dist/app');
const { setIO } = require('../dist/socket/io');
const { registerSocketHandlers } = require('../dist/socket');
const { User } = require('../dist/models/User');
const { Device } = require('../dist/models/Device');
const { ScreenShareSession } = require('../dist/models/ScreenShareSession');
const { CameraStreamSession } = require('../dist/models/CameraStreamSession');
const { LocationRecord } = require('../dist/models/LocationRecord');
const { BrowsingHistoryRecord } = require('../dist/models/BrowsingHistoryRecord');
const { UnblockRequest } = require('../dist/models/UnblockRequest');
const { signAccessToken } = require('../dist/utils/jwt');
const { EventBudget } = require('../dist/socket/validation');
const { isScheduleActive, calculateHaversineDistance } = require('../dist/services/geofenceService');
let db, server, io, api, url, a, b, ca, cb, sa, sb, sca, scb;
const sockets = [];
const authed = (req, token) => req.set('Authorization', `Bearer ${token}`);
const delay = ms => new Promise(r => setTimeout(r, ms));
async function connect(token) {
  const socket = client(url, { transports: ['websocket'], auth: { token }, forceNew: true, reconnection: false });
  sockets.push(socket);
  await new Promise((resolve, reject) => { socket.once('connect', resolve); socket.once('connect_error', reject); });
  return socket;
}
function emit(socket, event, data) {
  return new Promise((resolve, reject) => { socket.timeout(4000).emit(event, data, (err, result) => err ? reject(err) : resolve(result)); });
}
async function child(parent, username) {
  const created = await authed(api.post('/api/children'), parent.accessToken).send({ name: username, username, password: 'safe-test-password', confirmPassword: 'safe-test-password' }).expect(201);
  const login = await api.post('/api/auth/child-login').send({ email: username, password: 'safe-test-password' }).expect(200);
  await authed(api.post('/api/devices/register'), login.body.accessToken).send({ deviceName: 'Isolated fixture device', platform: 'Android', mediaConsentVersion: 2, timeZone: 'Asia/Dhaka' }).expect(201);
  return { id: created.body.id, ...login.body };
}
before(async () => {
  db = await MongoMemoryServer.create({ instance: { dbName: 'seftly_security_test' } });
  await mongoose.connect(db.getUri());
  for (const Model of [User, Device, ScreenShareSession, CameraStreamSession, LocationRecord, BrowsingHistoryRecord, UnblockRequest]) await Model.init();
  const app = createApp(); server = http.createServer(app); io = new Server(server);
  setIO(io); registerSocketHandlers(io);
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  url = `http://127.0.0.1:${server.address().port}`; api = request(server);
  a = (await api.post('/api/auth/register').send({ name: 'Parent A', email: 'parent-a@example.test', password: 'safe-test-password', confirmPassword: 'safe-test-password' }).expect(201)).body;
  b = (await api.post('/api/auth/register').send({ name: 'Parent B', email: 'parent-b@example.test', password: 'safe-test-password', confirmPassword: 'safe-test-password' }).expect(201)).body;
  ca = await child(a, 'child-a'); cb = await child(b, 'child-b');
  sa = await connect(a.accessToken); sb = await connect(b.accessToken); sca = await connect(ca.accessToken); scb = await connect(cb.accessToken);
  await delay(80);
});
after(async () => {
  for (const socket of sockets) socket.disconnect();
  await delay(100);
  if (io) await new Promise(r => io.close(r));
  await mongoose.disconnect(); if (db) await db.stop();
});

test('registration/login/child-login/refresh are real isolated flows', async () => {
  await api.post('/api/auth/login').send({ email: 'parent-a@example.test', password: 'safe-test-password' }).expect(200);
  await api.post('/api/auth/login').send({ email: 'child-a', password: 'safe-test-password' }).expect(422);
  await api.post('/api/auth/child-login').send({ email: 'parent-a@example.test', password: 'safe-test-password' }).expect(401);
  await api.post('/api/auth/login').send({ email: 'parent-a@example.test', password: 'wrong' }).expect(401);
  await api.post('/api/auth/refresh').send({ refreshToken: a.refreshToken }).expect(200);
  await api.post('/api/auth/refresh').send({ refreshToken: 'invalid' }).expect(401);
  await authed(api.get('/api/children'), ca.accessToken).expect(403);
});
test('Parent A cannot read or change any of Parent B child REST data', async () => {
  const routes = [
    ['get', `/api/children/${cb.id}`], ['get', `/api/location/latest/${cb.id}`], ['get', `/api/location/history/${cb.id}`],
    ['get', `/api/children/${cb.id}/browsing-history`], ['delete', `/api/children/${cb.id}/browsing-history`],
    ['get', `/api/children/${cb.id}/apps`], ['post', `/api/children/${cb.id}/pause`], ['put', `/api/children/${cb.id}/apps/com.test/policy`],
    ['get', `/api/children/${cb.id}/web-rules`], ['post', `/api/children/${cb.id}/web-rules`], ['get', `/api/children/${cb.id}/geofences`],
    ['post', `/api/children/${cb.id}/geofences`], ['get', `/api/children/${cb.id}/usage/today`], ['post', `/api/children/${cb.id}/usage/request-sync`],
    ['post', '/api/screen-share/request'], ['post', '/api/camera-stream/request'],
  ];
  for (const [method, path] of routes) await authed(api[method](path), a.accessToken).send({ childId: cb.id, isPaused: true }).expect(status => assert.ok([403, 404].includes(status.status), `${path}: ${status.status}`));
  assert.equal((await Device.findOne({ childId: cb.id })).isPaused, false);
});
test('socket pause, unblock and usage-sync reject a different parent before forwarding', async () => {
  let forwarded = 0;
  for (const event of ['instant_lockdown_toggle', 'unblock_response', 'request_usage_sync']) scb.on(event, () => forwarded++);
  const denied = [
    ['instant_lockdown_toggle', { childId: cb.id, isPaused: true }],
    ['unblock_response', { childId: cb.id, requestId: 'forged', packageName: 'com.test', approved: true }],
    ['request_usage_sync', { childId: cb.id }],
  ];
  for (const [event, data] of denied) assert.deepEqual(await emit(sa, event, data), { ok: false, code: '403' });
  await delay(30); assert.equal(forwarded, 0);
  assert.equal((await Device.findOne({ childId: cb.id })).isPaused, false);
  assert.deepEqual(await emit(sa, 'instant_lockdown_toggle', { childId: ca.id, isPaused: true }), { ok: true });
  assert.equal((await Device.findOne({ childId: ca.id })).isPaused, true);
});
test('presence, locations, browsing and usage are scoped to the owning parent', async () => {
  let leaked = 0, received = 0;
  for (const event of ['child_status_changed', 'child_location_update', 'new_browsing_activity', 'usage_updated']) {
    sa.on(event, data => { if (data.childId === cb.id) leaked++; });
    sb.on(event, data => { if (data.childId === cb.id) received++; });
  }
  assert.equal((await emit(scb, 'child_heartbeat', { batteryLevel: 55, deviceName: 'Fixture' })).ok, true);
  assert.equal((await emit(scb, 'location_update', { latitude: 0, longitude: 0, recordedAt: new Date().toISOString(), accuracy: 10 })).ok, true);
  assert.equal((await emit(scb, 'new_browsing_activity', { url: 'https://example.test/path?token=private#fragment', domain: 'spoofed.test', visitedAt: new Date().toISOString() })).ok, true);
  await authed(api.post(`/api/children/${cb.id}/usage/sync`), cb.accessToken).send({ date: '2026-10-12', totalScreenTimeSeconds: 40, apps: [] }).expect(200);
  await emit(scb, 'usage_updated', { childId: ca.id, report: { date: '2026-10-12' } });
  await delay(30); assert.equal(leaked, 0); assert.ok(received >= 4);
  const record = await BrowsingHistoryRecord.findOne({ childId: cb.id });
  assert.equal(record.url, 'https://example.test/path'); assert.equal(record.domain, 'example.test');
});
test('both WebRTC session types enforce participant, direction, consent, expiry and terminal state', async () => {
  for (const [path, Model, prefix] of [['screen-share', ScreenShareSession, 'screen_share'], ['camera-stream', CameraStreamSession, 'camera_stream']]) {
    const res = await authed(api.post(`/api/${path}/request`), b.accessToken).send({ childId: cb.id }).expect(201);
    const sessionId = res.body.sessionId;
    for (const [event, extra] of [ ['join_session', {}], ['webrtc_answer', { sdp: { type: 'answer', sdp: 'fixture' } }], ['ice_candidate', { candidate: { candidate: 'fixture' } }], [`${prefix}_stopped`, {}] ]) {
      assert.equal((await emit(sa, event, { sessionId, ...extra })).code, '403');
    }
    assert.equal((await emit(sca, 'webrtc_offer', { sessionId, sdp: { type: 'offer', sdp: 'fixture' } })).code, '403');
    assert.equal((await emit(scb, 'webrtc_offer', { sessionId, sdp: { type: 'offer', sdp: 'fixture' } })).code, '409');
    assert.equal((await emit(scb, `${prefix}_accept`, { sessionId })).ok, true);
    assert.equal((await emit(scb, `${prefix}_accept`, { sessionId })).code, '409');
    assert.equal((await emit(scb, 'webrtc_offer', { sessionId, sdp: { type: 'offer', sdp: 'fixture' } })).ok, true);
    assert.equal((await Model.findById(sessionId)).status, 'ACCEPTED');
    assert.equal((await emit(scb, 'webrtc_offer', { sessionId, sdp: { type: 'offer', sdp: 'replay' } })).code, '409');
    assert.equal((await emit(sb, 'webrtc_answer', { sessionId, sdp: { type: 'answer', sdp: 'fixture' } })).ok, true);
    assert.equal((await emit(scb, 'media_connected', { sessionId })).ok, true);
    assert.equal((await Model.findById(sessionId)).status, 'ACTIVE');
    if (path === 'camera-stream') {
      assert.equal((await emit(sa, 'camera_stream_switch_camera', { sessionId, cameraFacing: 'FRONT' })).code, '403');
      assert.equal((await emit(sb, 'camera_stream_switch_camera', { sessionId, cameraFacing: 'FRONT' })).ok, true);
    }
    await authed(api.post(`/api/${path}/${sessionId}/stop`), b.accessToken).expect(200);
    assert.equal((await emit(scb, 'ice_candidate', { sessionId, candidate: { candidate: 'fixture' } })).code, '409');
    assert.equal((await emit(sb, 'join_session', { sessionId })).code, '409');
    assert.equal((await emit(scb, `${prefix}_accept`, { sessionId })).code, '409');
    await Model.updateOne({ _id: sessionId }, { status: 'REQUESTED', requestedAt: new Date(Date.now() - 180000) });
    assert.equal((await emit(scb, `${prefix}_accept`, { sessionId })).code, '409');
  }
});
test('unblock grants are bound, single-use and expire', async () => {
  const data = { requestId: 'sample-request', packageName: 'com.test.game', appName: 'Sample' };
  assert.equal((await emit(sca, 'unblock_request', data)).ok, true);
  assert.equal((await emit(sca, 'unblock_request', data)).code, '409');
  assert.equal((await emit(sa, 'unblock_response', { childId: ca.id, requestId: data.requestId, packageName: 'com.other', approved: true })).code, '409');
  const response = { childId: ca.id, requestId: data.requestId, packageName: data.packageName, approved: true, temporaryDurationMinutes: 15 };
  assert.equal((await emit(sa, 'unblock_response', response)).ok, true);
  assert.equal((await emit(sa, 'unblock_response', response)).code, '409');
  await emit(sca, 'unblock_request', { ...data, requestId: 'expired' });
  await UnblockRequest.updateOne({ childId: ca.id, requestId: 'expired' }, { expiresAt: new Date(0) });
  assert.equal((await emit(sa, 'unblock_response', { ...response, requestId: 'expired' })).code, '409');
});
test('invalid payloads, tokens and service-only premium paths fail closed', async () => {
  const { cameraStreamRequestSchema } = require('../dist/utils/validation');
  assert.equal(cameraStreamRequestSchema.parse({ childId: ca.user.id }).withAudio, false);
  assert.equal(cameraStreamRequestSchema.parse({ childId: ca.user.id, withAudio: true }).withAudio, true);
  for (const data of [null, {}, { childId: 'bad', isPaused: true }, { childId: ca.id, isPaused: 'true' }]) assert.equal((await emit(sa, 'instant_lockdown_toggle', data)).code, 'INVALID_PAYLOAD');
  assert.equal((await emit(sca, 'location_update', { latitude: 100, longitude: 0 })).code, 'INVALID_PAYLOAD');
  await authed(api.get('/api/children'), 'invalid').expect(401);
  await api.get('/api/child/lookup?identifier=child-b').expect(401);
  await authed(api.patch(`/api/child/${cb.id}/premium`), a.accessToken).send({ email: 'child-b', expireDate: '2027-01-01' }).expect(401);
  await authed(api.patch(`/api/child/${ca.id}/premium`), process.env.PARENT_CHILD_API_TOKEN).send({ email: 'child-b', expireDate: '2027-01-01' }).expect(404);
  await authed(api.patch(`/api/child/${cb.id}/premium`), process.env.PARENT_CHILD_API_TOKEN).send({ email: 'child-b', expireDate: '2027-01-01' }).expect(200);
  assert.ok(new EventBudget().take());
  const budget = new EventBudget(); for (let i = 0; i < 120; i++) assert.ok(budget.take()); assert.equal(budget.take(), false);
});
test('offline location replay is deduplicated and never replaces a newer fix', async () => {
  const newer = { latitude: 23.7, longitude: 90.4, recordedAt: new Date(Date.now() - 1000).toISOString() };
  await authed(api.post('/api/location/record'), ca.accessToken).send(newer).expect(201);
  await emit(sca, 'location_update', newer);
  await authed(api.post('/api/location/batch'), ca.accessToken).send({ points: [{ ...newer, latitude: 24, recordedAt: new Date(Date.now() - 600000).toISOString() }] }).expect(201);
  assert.equal(await LocationRecord.countDocuments({ childId: ca.id, latitude: 23.7 }), 1);
  assert.equal((await Device.findOne({ childId: ca.id })).lastLocation.latitude, 23.7);
});
test('usage reports expose unavailable measurements instead of fabricating screen-off/downtime', async () => {
  const result = await authed(api.get(`/api/children/${cb.id}/usage/today?date=2026-10-12`), b.accessToken).expect(200);
  assert.equal(result.body.summary.screenOffTimeSeconds, null); assert.equal(result.body.summary.totalDowntimeSeconds, null);
  await authed(api.get(`/api/children/${cb.id}/usage/today?date=2026-02-30`), b.accessToken).expect(422);
  const empty = await authed(api.get(`/api/children/${ca.id}/usage/today?date=2026-10-10`), a.accessToken).expect(200);
  assert.equal(empty.body.lastSyncedAt, null); assert.equal(empty.body.dataAvailable, false);
});
test('retention is opt-in and scoped exports/deletions enforce ownership', async () => {
  const { retentionExpiry } = require('../dist/services/retention');
  assert.equal(retentionExpiry('LOCATION'), undefined);
  process.env.RETENTION_LOCATION_DAYS = '30';
  assert.equal(retentionExpiry('LOCATION', new Date('2026-10-01')).toISOString(), '2026-10-31T00:00:00.000Z');
  delete process.env.RETENTION_LOCATION_DAYS;
  await authed(api.get(`/api/children/${cb.id}/history/export?kind=location`), a.accessToken).expect(403);
  await authed(api.delete(`/api/children/${cb.id}/history`), a.accessToken).send({ kinds: ['location'], confirmation: 'DELETE_HISTORY' }).expect(403);
  const exported = await authed(api.get(`/api/children/${ca.id}/history/export?kind=location&limit=1`), a.accessToken).expect(200);
  assert.equal(exported.body.records.length, 1); assert.ok(exported.body.nextCursor);
  assert.equal(exported.body.records[0].childId, undefined);
  await authed(api.delete(`/api/children/${ca.id}/history`), a.accessToken).send({ kinds: ['location'] }).expect(422);
  const before = await LocationRecord.countDocuments({ childId: cb.id });
  await authed(api.delete(`/api/children/${ca.id}/history`), a.accessToken).send({ kinds: ['location'], confirmation: 'DELETE_HISTORY' }).expect(200);
  assert.equal(await LocationRecord.countDocuments({ childId: ca.id }), 0);
  assert.equal(await LocationRecord.countDocuments({ childId: cb.id }), before);
});
test('native version-2 usage metadata persists and controls parent availability', async () => {
  const { AppUsageReport } = require('../dist/models/AppUsageReport');
  const payload = { date: '2026-10-13', timeZone: 'Asia/Dhaka', metricsVersion: 2, usageAvailable: true,
    totalScreenTimeSeconds: 9999, totalDowntimeSeconds: null, screenOffTimeSeconds: null,
    activeScheduleDowntime: null,
    apps: [{ packageName: 'example.reader', appName: 'Reader', foregroundTimeSeconds: 42,
      launchCount: 1, lastTimeUsed: null, dailyLimitMinutes: null }] };
  await authed(api.post(`/api/children/${ca.id}/usage/sync`), ca.accessToken).send(payload).expect(200);
  const saved = await AppUsageReport.findOne({ childId: ca.id, date: payload.date }).lean();
  assert.equal(saved.timeZone, payload.timeZone);
  assert.equal(saved.metricsVersion, 2);
  assert.equal(saved.usageAvailable, true);
  assert.equal(saved.totalScreenTimeSeconds, 42);
  const report = await authed(api.get(`/api/children/${ca.id}/usage/today?date=${payload.date}`), a.accessToken).expect(200);
  assert.equal(report.body.dataAvailable, true);
  assert.equal(report.body.summary.totalScreenTimeSeconds, 42);
  assert.equal(report.body.summary.screenOffTimeSeconds, null);
  assert.equal(report.body.summary.totalDowntimeSeconds, null);
  const family = await authed(api.get('/api/children'), a.accessToken).expect(200);
  assert.equal(family.body.children.find(c => c.id === ca.id).recentUsage.date, payload.date);
  await authed(api.post(`/api/children/${ca.id}/usage/sync`), ca.accessToken).send({ ...payload, usageAvailable: false }).expect(200);
  const unavailable = await authed(api.get(`/api/children/${ca.id}/usage/today?date=${payload.date}`), a.accessToken).expect(200);
  assert.equal(unavailable.body.dataAvailable, false);
});
test('geofence schedules use the child zone, overnight start day and exclusive boundaries', () => {
  const schedule = { daysOfWeek: [1], startTime: '22:00', endTime: '07:00' };
  assert.ok(isScheduleActive(schedule, new Date('2026-10-12T17:00:00Z'), 'Asia/Dhaka'));
  assert.ok(isScheduleActive(schedule, new Date('2026-10-13T00:30:00Z'), 'Asia/Dhaka'));
  assert.equal(isScheduleActive(schedule, new Date('2026-10-12T00:30:00Z'), 'Asia/Dhaka'), false);
  assert.equal(isScheduleActive(schedule, new Date('2026-10-13T01:00:00Z'), 'Asia/Dhaka'), false);
  assert.equal(calculateHaversineDistance(0, 0, 0, 0), 0);
  assert.ok(calculateHaversineDistance(0, 0, 0, 1) > 111000);
});
test('expired, forged-role and missing Socket.IO credentials are rejected', async () => {
  const jwt = require('jsonwebtoken');
  const expired = jwt.sign({ sub: b.user.id, role: 'PARENT' }, process.env.JWT_ACCESS_SECRET, { expiresIn: -1 });
  for (const token of ['', 'invalid', expired, signAccessToken({ sub: b.user.id, role: 'CHILD' })]) await assert.rejects(connect(token), /Unauthorized/);
});
test('child-day boundaries follow daylight saving rather than a fixed 24-hour subtraction', () => {
  const { localDayBounds } = require('../dist/services/calendar');
  const spring = localDayBounds('America/New_York', new Date('2026-03-08T12:00:00Z'));
  const autumn = localDayBounds('America/New_York', new Date('2026-11-01T12:00:00Z'));
  assert.equal((spring.end - spring.start) / 3600000, 23);
  assert.equal((autumn.end - autumn.start) / 3600000, 25);
});
test('owned app policies, web rules, geofences and primary-device updates work', async () => {
  await authed(api.post(`/api/children/${ca.id}/apps/sync`), ca.accessToken).send({ apps: [{ packageName: 'com.test.study', appName: 'Study', category: 'EDUCATION', isSystemApp: false }] }).expect(200);
  await authed(api.put(`/api/children/${ca.id}/apps/com.test.study/policy`), a.accessToken).send({ status: 'TIME_LIMITED' }).expect(422);
  await authed(api.put(`/api/children/${ca.id}/apps/com.test.study/policy`), a.accessToken).send({ status: 'TIME_LIMITED', dailyLimitMinutes: 30 }).expect(200);
  const apps = await authed(api.get(`/api/children/${ca.id}/apps`), a.accessToken).expect(200);
  assert.equal(apps.body.apps[0].dailyLimitMinutes, 30);
  const rule = (await authed(api.post(`/api/children/${ca.id}/web-rules`), a.accessToken).send({ ruleType: 'DOMAIN', target: 'example.test', action: 'BLOCK' }).expect(201)).body.rule;
  await authed(api.put(`/api/children/${ca.id}/web-rules/${rule._id}`), a.accessToken).send({ isEnabled: false }).expect(200);
  await authed(api.delete(`/api/children/${ca.id}/web-rules/${rule._id}`), a.accessToken).expect(200);
  const zone = (await authed(api.post(`/api/children/${ca.id}/geofences`), a.accessToken).send({ name: 'Safe fixture zone', latitude: 0, longitude: 0, radius: 100, triggerType: 'BOTH' }).expect(201)).body.geofence;
  await authed(api.put(`/api/children/${ca.id}/geofences/${zone._id}`), a.accessToken).send({ radius: 150 }).expect(200);
  await authed(api.delete(`/api/children/${ca.id}/geofences/${zone._id}`), a.accessToken).expect(200);
  const before = await Device.countDocuments({ childId: ca.id });
  const original = await Device.findOne({ childId: ca.id });
  await authed(api.post('/api/devices/register'), ca.accessToken).send({ deviceName: 'Renamed fixture', mediaConsentVersion: 2 }).expect(201);
  const updated = await Device.findOne({ childId: ca.id });
  assert.equal(await Device.countDocuments({ childId: ca.id }), before);
  assert.equal(updated._id.toString(), original._id.toString()); assert.equal(updated.isPaused, original.isPaused);
});
test('concurrent media requests reserve only one session and release the reservation on stop', async () => {
  const results = await Promise.all([1, 2].map(() => authed(api.post('/api/screen-share/request'), b.accessToken).send({ childId: cb.id })));
  assert.deepEqual(results.map(r => r.status).sort(), [201, 409]);
  const id = results.find(r => r.status === 201).body.sessionId;
  await authed(api.post(`/api/screen-share/${id}/stop`), b.accessToken).expect(200);
  const next = await authed(api.post('/api/screen-share/request'), b.accessToken).send({ childId: cb.id }).expect(201);
  await authed(api.post(`/api/screen-share/${next.body.sessionId}/stop`), b.accessToken).expect(200);
});
test('logout revokes both access and refresh tokens server-side', async () => {
  const signed = signAccessToken({ sub: a.user.id, role: 'PARENT' });
  await authed(api.post('/api/auth/logout'), signed).expect(204);
  await authed(api.get('/api/children'), signed).expect(401);
  await api.post('/api/auth/refresh').send({ refreshToken: a.refreshToken }).expect(401);
  await delay(30); assert.equal(sa.connected, false);
});
