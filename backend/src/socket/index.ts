import { AudioSession } from "../models/AudioSession";
import { featureEnabled } from "../services/features";
import { MediaLease } from "../models/MediaLease";
import { releaseMediaSession, notifySessionEnd } from "../services/mediaSessions";
import { Model } from "mongoose";
import { IScreenShareSession } from "../models/ScreenShareSession";
import { Server, Socket } from "socket.io";
import { z } from "zod";
import { verifyAccessToken } from "../utils/jwt";
import { Device } from "../models/Device";
import { ScreenShareSession } from "../models/ScreenShareSession";
import { CameraStreamSession } from "../models/CameraStreamSession";
import { User } from "../models/User";
import { AppUsageReport } from "../models/AppUsageReport";
import { UnblockRequest } from "../models/UnblockRequest";
import { AppError } from "../utils/http";
import { recordLocationSchema, recordBrowsingHistorySchema } from "../utils/validation";
import { ingestLocation } from "../services/locationIngestion";
import { ingestBrowsing } from "../services/browsingIngestion";
import { Actor, ownedChild, assertSessionParticipant, openSessionStates, sessionExpired } from "../services/authorization";
import { EventBudget, sessionPayload, childPayload, heartbeatPayload, sdpPayload, icePayload, unblockRequestPayload, unblockResponsePayload } from "./validation";
import { setChildSocket, removeChildSocket, getChildSocketIds, addParentSocket, removeParentSocket, getParentSocketIds } from "./presence";

type SocketActor = Actor & { token: string };
type Ack = (result: { ok: boolean; code?: string }) => void;
const sessionModels: Model<IScreenShareSession>[] = [ScreenShareSession, CameraStreamSession as unknown as Model<IScreenShareSession>, AudioSession];
const sessionPrefixes = ["screen_share", "camera_stream", "audio_session"] as const;

export function registerSocketHandlers(io: Server): void {
  const emitParent = (parentId: string, event: string, data: unknown) => {
    for (const id of getParentSocketIds(parentId)) io.to(id).emit(event, data);
  };
  async function endUserSessions(userId: string, role: Actor["role"], reason: string) {
    for (const [index, Model] of sessionModels.entries()) {
      const sessions = await Model.find({ [role === "CHILD" ? "childId" : "parentId"]: userId, status: { $in: openSessionStates } });
      for (const session of sessions) {
        const changed = await Model.updateOne({ _id: session._id, status: { $in: openSessionStates } }, { $set: { status: "ENDED", endedAt: new Date(), endedBy: "SYSTEM" } });
        if (changed.modifiedCount) { await releaseMediaSession(session.id); notifySessionEnd(session, `${sessionPrefixes[index]}_stopped`, "SYSTEM", reason); }
      }
    }
  }
  // Sweep pending and active sessions. Timers are stopped when the server closes.
  const sweep = setInterval(() => {
    void (async () => {
      for (const [index, Model] of sessionModels.entries()) {
        const sessions = await Model.find({ status: { $in: openSessionStates } });
        for (const session of sessions) if (sessionExpired(session)) {
          const changed = await Model.updateOne({ _id: session._id, status: session.status }, { $set: { status: "ENDED", endedAt: new Date(), endedBy: "SYSTEM" } });
          if (changed.modifiedCount) { await releaseMediaSession(session.id); notifySessionEnd(session, `${sessionPrefixes[index]}_stopped`, "SYSTEM", "session_expired"); }
        }
      }
    })().catch(() => console.error("[socket] session expiry check failed"));
  }, 10_000);
  sweep.unref();
  io.engine.on("close", () => clearInterval(sweep));

  io.use((socket, next) => {
    void (async () => {
      const token = socket.handshake.auth?.token;
      if (typeof token !== "string" || token.length > 4096) throw new AppError("Unauthorized", 401);
      const payload = verifyAccessToken(token);
      const user = await User.findById(payload.sub);
      if (!user || user.role !== payload.role || user.refreshTokenVersion !== (payload.tokenVersion ?? 0)) throw new AppError("Unauthorized", 401);
      socket.data = { userId: user.id, role: user.role, token } satisfies SocketActor;
    })().then(() => next(), () => next(new Error("Unauthorized")));
  });

  io.on("connection", (socket: Socket) => {
    const actor = socket.data as SocketActor;
    const { userId, role } = actor;
    const budget = new EventBudget();
    // Expired tokens cannot keep a privileged socket alive indefinitely.
    const expiresAt = verifyAccessToken(actor.token).exp! * 1000;
    const expiryTimer = setTimeout(() => socket.disconnect(true), Math.max(0, Math.min(expiresAt - Date.now(), 2_147_483_647)));
    expiryTimer.unref();
    const requireChild = () => { if (role !== "CHILD") throw new AppError("Forbidden", 403); };
    const requireParent = () => { if (role !== "PARENT") throw new AppError("Forbidden", 403); };
    function on<T>(event: string, schema: z.ZodType<T>, handler: (data: T) => Promise<void>) {
      socket.on(event, (raw: unknown, ack?: Ack) => {
        void (async () => {
          if (!budget.take()) throw new AppError("Rate limited", 429);
          const data = schema.parse(raw);
          const payload = verifyAccessToken(actor.token);
          const user = await User.findById(userId);
          if (!user || user.role !== role || user.refreshTokenVersion !== (payload.tokenVersion ?? 0)) throw new AppError("Unauthorized", 401);
          await handler(data);
          if (typeof ack === "function") ack({ ok: true });
        })().catch((error: unknown) => {
          const code = error instanceof z.ZodError ? "INVALID_PAYLOAD" : error instanceof AppError ? String(error.statusCode) : "SERVER_ERROR";
          if (typeof ack === "function") ack({ ok: false, code });
          socket.emit("operation_error", { event, code });
          if (code === "401") socket.disconnect(true);
          if (code === "SERVER_ERROR") console.error(`[socket] ${event} failed`);
        });
      });
    }
    async function sessionFor(sessionId: string, states = openSessionStates, kind?: "screen" | "camera" | "audio", enforceConsent = true) {
      const index = kind === "screen" ? 0 : kind === "camera" ? 1 : kind === "audio" ? 2 : undefined;
      let foundIndex = -1;
      let session: IScreenShareSession | null = null;
      for (const candidate of index === undefined ? [0, 1, 2] : [index]) {
        session = await sessionModels[candidate].findById(sessionId);
        if (session) { foundIndex = candidate; break; }
      }
      if (!session) throw new AppError("Session not found", 404);
      assertSessionParticipant(actor, session, states);
      if (enforceConsent) {
        const device = await Device.findOne({ childId: session.childId }).sort({ updatedAt: -1 }).select("mediaConsentVersion audioCheckInVersion").lean();
        if (device?.mediaConsentVersion !== 2) throw new AppError("Update Seftly Child to enable consent", 409);
        if (foundIndex === 2 && (!featureEnabled("AUDIO") || device.audioCheckInVersion !== 1)) throw new AppError("Audio check-in is unavailable", 409);
      }
      await ownedChild({ userId: session.parentId.toString(), role: "PARENT" }, session.childId.toString());
      return { session, Model: sessionModels[foundIndex], kind: sessionPrefixes[foundIndex] };
    }
    const joinParticipants = (session: { _id: { toString(): string }; parentId: { toString(): string }; childId: { toString(): string } }) => {
      for (const id of [...getParentSocketIds(session.parentId.toString()), ...getChildSocketIds(session.childId.toString())]) {
        io.sockets.sockets.get(id)?.join(`session:${session._id.toString()}`);
      }
    };

    if (role === "CHILD") setChildSocket(userId, socket.id); else addParentSocket(userId, socket.id);
    void (async () => {
      if (role === "CHILD") {
        const now = new Date();
        const device = await Device.findOneAndUpdate({ childId: userId }, { status: "ONLINE", lastSeen: now, socketId: socket.id }, { sort: { updatedAt: -1 }, new: true });
        const child = await User.findById(userId);
        if (socket.connected && child?.parentId) emitParent(child.parentId.toString(), "child_status_changed", { childId: userId, status: "ONLINE", lastSeen: now, deviceName: device?.deviceName });
      } else {
        const children = await User.find({ parentId: userId, role: "CHILD" }).select("_id").lean();
        const statuses = await Promise.all(children.map(async (child) => {
          const device = await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean();
          return { childId: child._id.toString(), status: getChildSocketIds(child._id.toString()).length ? "ONLINE" : "OFFLINE", lastSeen: device?.lastSeen ?? null, deviceName: device?.deviceName, platform: device?.platform };
        }));
        if (socket.connected) socket.emit("initial_children_presence", { children: statuses });
      }
    })().catch(() => { socket.emit("operation_error", { event: "presence", code: "SERVER_ERROR" }); socket.disconnect(true); });

    on("child_heartbeat", heartbeatPayload, async (data) => {
      requireChild();
      const now = new Date();
      const update: Record<string, unknown> = { status: "ONLINE", lastSeen: now, socketId: socket.id };
      if (data.batteryLevel !== undefined) update["lastLocation.batteryLevel"] = data.batteryLevel;
      if (data.deviceName) update.deviceName = data.deviceName;
      const device = await Device.findOneAndUpdate({ childId: userId }, { $set: update }, { sort: { updatedAt: -1 }, new: true });
      const child = await User.findById(userId);
      if (child?.parentId) emitParent(child.parentId.toString(), "child_status_changed", { childId: userId, status: "ONLINE", lastSeen: now, batteryLevel: data.batteryLevel, deviceName: device?.deviceName });
    });
    on("join_session", sessionPayload, async ({ sessionId }) => {
      await sessionFor(sessionId);
      await socket.join(`session:${sessionId}`);
    });
    for (const kind of ["screen", "camera", "audio"] as const) {
      const prefix = kind === "screen" ? "screen_share" : kind === "camera" ? "camera_stream" : "audio_session";
      on(`${prefix}_accept`, sessionPayload, async ({ sessionId }) => {
        requireChild();
        const { session, Model } = await sessionFor(sessionId, ["REQUESTED"], kind);
        const changed = await Model.updateOne({ _id: session._id, status: "REQUESTED" }, { $set: { status: "ACCEPTED" } });
        if (!changed.modifiedCount) throw new AppError("Request already handled", 409);
        joinParticipants(session);
        io.to(`session:${sessionId}`).emit(`${prefix}_accept`, { sessionId });
      });
      on(`${prefix}_reject`, sessionPayload.extend({ reason: z.string().max(200).optional() }), async ({ sessionId, reason }) => {
        requireChild();
        const { session, Model } = await sessionFor(sessionId, ["REQUESTED"], kind);
        const changed = await Model.updateOne({ _id: session._id, status: "REQUESTED" }, { $set: { status: "REJECTED", endedAt: new Date(), endedBy: "CHILD" } });
        if (!changed.modifiedCount) throw new AppError("Request already handled", 409);
        emitParent(session.parentId.toString(), `${prefix}_reject`, { sessionId, reason });
        await releaseMediaSession(sessionId);
        io.in(`session:${sessionId}`).socketsLeave(`session:${sessionId}`);
      });
      on(`${prefix}_stopped`, sessionPayload, async ({ sessionId }) => {
        const { Model, session } = await sessionFor(sessionId, openSessionStates, kind, false);
        await Model.updateOne({ _id: session._id, status: { $in: openSessionStates } }, { $set: { status: "ENDED", endedAt: new Date(), endedBy: role } });
        joinParticipants(session);
        await releaseMediaSession(sessionId);
        notifySessionEnd(session, `${prefix}_stopped`, role);
      });
    }
    on("camera_stream_switch_camera", sessionPayload.extend({ cameraFacing: z.enum(["BACK", "FRONT"]) }), async ({ sessionId, cameraFacing }) => {
      requireParent();
      const { session } = await sessionFor(sessionId, ["ACTIVE"], "camera");
      await CameraStreamSession.updateOne({ _id: session._id, status: "ACTIVE" }, { $set: { cameraFacing } });
      socket.to(`session:${sessionId}`).emit("camera_stream_switch_camera", { sessionId, cameraFacing });
    });
    on("webrtc_offer", sdpPayload, async ({ sessionId, sdp }) => {
      requireChild();
      if (sdp.type !== "offer") throw new AppError("Invalid offer", 400);
      const { session, Model } = await sessionFor(sessionId, ["ACCEPTED"]);
      const device = await Device.findOne({ childId: session.childId }).sort({ updatedAt: -1 }).select("mediaConsentVersion").lean();
      if (device?.mediaConsentVersion !== 2) throw new AppError("Update Seftly Child to enable consent", 409);
      const changed = await Model.updateOne({ _id: session._id, status: "ACCEPTED", offerSentAt: null }, { $set: { offerSentAt: new Date() } });
      if (!changed.modifiedCount) throw new AppError("Offer already handled", 409);
      joinParticipants(session);
      socket.to(`session:${sessionId}`).emit("webrtc_offer", { sessionId, sdp });
    });
    on("webrtc_answer", sdpPayload, async ({ sessionId, sdp }) => {
      requireParent();
      if (sdp.type !== "answer") throw new AppError("Invalid answer", 400);
      const { session, Model } = await sessionFor(sessionId, ["ACCEPTED"]);
      const changed = await Model.updateOne({ _id: session._id, status: "ACCEPTED", offerSentAt: { $ne: null }, answerReceivedAt: null }, { $set: { answerReceivedAt: new Date() } });
      if (!changed.modifiedCount) throw new AppError("Answer unavailable or already handled", 409);
      socket.to(`session:${sessionId}`).emit("webrtc_answer", { sessionId, sdp });
    });
    on("ice_candidate", icePayload, async ({ sessionId, candidate }) => {
      await sessionFor(sessionId, ["ACCEPTED", "ACTIVE"]);
      socket.to(`session:${sessionId}`).emit("ice_candidate", { sessionId, candidate });
    });
    on("media_connected", sessionPayload, async ({ sessionId }) => {
      requireChild();
      const { Model, session, kind } = await sessionFor(sessionId, ["ACCEPTED"]);
      const changed = await Model.updateOne({ _id: session._id, status: "ACCEPTED", offerSentAt: { $ne: null }, answerReceivedAt: { $ne: null } }, { $set: { status: "ACTIVE", startedAt: new Date() } });
      if (!changed.modifiedCount) throw new AppError("Session negotiation incomplete", 409);
      await MediaLease.updateMany({ sessionId }, { $set: { expiresAt: new Date(Date.now() + 30 * 60_000) } });
      if (changed.modifiedCount) io.to(`session:${sessionId}`).emit(`${kind}_started`, { sessionId });
    });
    on("location_update", recordLocationSchema, async (data) => {
      requireChild();
      await ingestLocation(userId, data);
    });
    on("new_browsing_activity", recordBrowsingHistorySchema, async (data) => {
      requireChild();
      await ingestBrowsing(userId, [data]);
    });
    on("unblock_request", unblockRequestPayload, async (data) => {
      requireChild();
      const child = await User.findById(userId);
      if (!child?.parentId) throw new AppError("Child unavailable", 403);
      const exists = await UnblockRequest.findOne({ childId: userId, requestId: data.requestId });
      if (exists) throw new AppError("Duplicate request", 409);
      await UnblockRequest.create({ _id: `${userId}:${data.requestId}`, childId: userId, parentId: child.parentId, requestId: data.requestId, packageName: data.packageName, expiresAt: new Date(Date.now() + 10 * 60_000) });
      emitParent(child.parentId.toString(), "unblock_request", { ...data, childId: userId, childName: child.name, requestedAt: new Date().toISOString() });
    });
    on("unblock_response", unblockResponsePayload, async (data) => {
      await ownedChild(actor, data.childId);
      const request = await UnblockRequest.findOneAndUpdate({ childId: data.childId, parentId: userId, requestId: data.requestId, packageName: data.packageName, resolvedAt: null, expiresAt: { $gt: new Date() } }, { $set: { resolvedAt: new Date() } }, { new: true });
      if (!request) throw new AppError("Request expired or already resolved", 409);
      for (const id of getChildSocketIds(data.childId)) io.to(id).emit("unblock_response", { ...data, temporaryDurationMinutes: data.approved ? data.temporaryDurationMinutes ?? 15 : 0 });
    });
    on("instant_lockdown_toggle", childPayload.extend({ isPaused: z.boolean() }), async (data) => {
      await ownedChild(actor, data.childId);
      await Device.updateMany({ childId: data.childId }, { $set: { isPaused: data.isPaused } });
      for (const id of getChildSocketIds(data.childId)) io.to(id).emit("instant_lockdown_toggle", { isPaused: data.isPaused });
    });
    on("request_usage_sync", childPayload, async ({ childId }) => {
      await ownedChild(actor, childId);
      for (const id of getChildSocketIds(childId)) io.to(id).emit("request_usage_sync", { childId, requestedAt: new Date().toISOString() });
    });
    on("usage_updated", z.object({ report: z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }) }), async ({ report }) => {
      requireChild();
      const child = await User.findById(userId);
      const saved = await AppUsageReport.findOne({ childId: userId, date: report.date }).lean();
      if (child?.parentId && saved) emitParent(child.parentId.toString(), "usage_updated", { childId: userId, date: saved.date, report: saved });
    });
    socket.on("disconnect", () => {
      clearTimeout(expiryTimer);
      const last = role === "CHILD" ? removeChildSocket(userId, socket.id) : (removeParentSocket(userId, socket.id), getParentSocketIds(userId).length === 0);
      if (!last) return;
      void (async () => {
        if (role === "CHILD") {
          await Device.updateMany({ childId: userId }, { $set: { status: "OFFLINE", socketId: null } });
          const child = await User.findById(userId);
          if (child?.parentId && !getChildSocketIds(userId).length) emitParent(child.parentId.toString(), "child_status_changed", { childId: userId, status: "OFFLINE" });
        }
        // Reconnection requires a new request and fresh consent; media grants are never reused.
        if (!(role === "CHILD" ? getChildSocketIds(userId) : getParentSocketIds(userId)).length) await endUserSessions(userId, role, `${role.toLowerCase()}_disconnected`);
      })().catch(() => console.error("[socket] disconnect cleanup failed"));
    });
  });
}
