import { Server, Socket } from "socket.io";
import { verifyAccessToken } from "../utils/jwt";
import { Device } from "../models/Device";
import { ScreenShareSession } from "../models/ScreenShareSession";
import { CameraStreamSession } from "../models/CameraStreamSession";
import { LocationRecord } from "../models/LocationRecord";
import { User } from "../models/User";
import { BrowsingHistoryRecord } from "../models/BrowsingHistoryRecord";
import { evaluateChildGeofences } from "../services/geofenceService";

import {
  setChildSocket,
  removeChildSocket,
  getChildSocketIds,
  addParentSocket,
  removeParentSocket,
  getParentSocketIds,
  findChildIdBySocket,
} from "./presence";

interface SocketAuthPayload {
  userId: string;
  role: "PARENT" | "CHILD";
}

function authenticateSocket(socket: Socket): SocketAuthPayload {
  const token = socket.handshake.auth?.token as string | undefined;
  if (!token) throw new Error("Missing auth token");
  const payload = verifyAccessToken(token);
  return { userId: payload.sub, role: payload.role };
}

export function registerSocketHandlers(io: Server): void {
  io.use((socket, next) => {
    try {
      const auth = authenticateSocket(socket);
      (socket.data as SocketAuthPayload) = auth;
      next();
    } catch (err) {
      next(new Error("Unauthorized"));
    }
  });

  io.on("connection", async (socket: Socket) => {
    const { userId, role } = socket.data as SocketAuthPayload;

    if (role === "CHILD") {
      setChildSocket(userId, socket.id);
      const now = new Date();
      const updatedDev = await Device.findOneAndUpdate(
        { childId: userId },
        { status: "ONLINE", lastSeen: now, socketId: socket.id },
        { sort: { updatedAt: -1 }, new: true }
      );
      // Let any connected parent dashboards know this child came online.
      socket.broadcast.emit("child_status_changed", {
        childId: userId,
        status: "ONLINE",
        lastSeen: now,
        deviceName: updatedDev?.deviceName ?? "Child Device",
      });
    } else if (role === "PARENT") {
      addParentSocket(userId, socket.id);
      try {
        const children = await User.find({ parentId: userId, role: "CHILD" }).select("_id name username").lean();
        const childrenStatus = await Promise.all(
          children.map(async (ch) => {
            const childIdStr = ch._id.toString();
            const liveSockets = getChildSocketIds(childIdStr);
            const isOnline = liveSockets.length > 0;
            const device = await Device.findOne({ childId: childIdStr }).sort({ updatedAt: -1 }).lean();
            return {
              childId: childIdStr,
              status: isOnline ? "ONLINE" : (device?.status || "OFFLINE"),
              lastSeen: isOnline ? new Date() : (device?.lastSeen || new Date()),
              deviceName: device?.deviceName ?? "Child Device",
              platform: device?.platform ?? "Android",
            };
          })
        );
        socket.emit("initial_children_presence", { children: childrenStatus });
      } catch (err) {
        console.error("Error sending initial_children_presence:", err);
      }
    }

    // Handle periodic heartbeat from active child monitoring service
    socket.on("child_heartbeat", async (data: { batteryLevel?: number; isGpsOn?: boolean; deviceName?: string }) => {
      if (role !== "CHILD") return;
      try {
        const now = new Date();
        const updateDoc: any = { status: "ONLINE", lastSeen: now, socketId: socket.id };
        if (typeof data?.batteryLevel === "number") {
          updateDoc["lastLocation.batteryLevel"] = data.batteryLevel;
        }
        if (data?.deviceName) {
          updateDoc.deviceName = data.deviceName;
        }
        const updatedDev = await Device.findOneAndUpdate(
          { childId: userId },
          { $set: updateDoc },
          { sort: { updatedAt: -1 }, new: true }
        );

        socket.broadcast.emit("child_status_changed", {
          childId: userId,
          status: "ONLINE",
          lastSeen: now,
          batteryLevel: data?.batteryLevel,
          deviceName: updatedDev?.deviceName ?? "Child Device",
        });
      } catch (err) {
        console.error("Error handling child_heartbeat:", err);
      }
    });

    // Auto-join any active/requested sessions for this user so reconnected sockets stay in sync
    try {
      const activeScreenSessions = await ScreenShareSession.find({
        $or: [
          { parentId: userId, status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] } },
          { childId: userId, status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] } },
        ],
      });
      for (const s of activeScreenSessions) {
        socket.join(`session:${s.id}`);
      }

      const activeCameraSessions = await CameraStreamSession.find({
        $or: [
          { parentId: userId, status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] } },
          { childId: userId, status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] } },
        ],
      });
      for (const s of activeCameraSessions) {
        socket.join(`session:${s.id}`);
      }
    } catch {
      // ignore lookup error on socket connect
    }

    // ---- Explicit room joining ----
    socket.on("join_session", async ({ sessionId }: { sessionId: string }) => {
      if (!sessionId) return;
      const screenSession = await ScreenShareSession.findById(sessionId);
      if (screenSession) {
        const isParticipant =
          (role === "PARENT" && screenSession.parentId.toString() === userId) ||
          (role === "CHILD" && screenSession.childId.toString() === userId);
        if (isParticipant) socket.join(`session:${sessionId}`);
        return;
      }

      const cameraSession = await CameraStreamSession.findById(sessionId);
      if (cameraSession) {
        const isParticipant =
          (role === "PARENT" && cameraSession.parentId.toString() === userId) ||
          (role === "CHILD" && cameraSession.childId.toString() === userId);
        if (isParticipant) socket.join(`session:${sessionId}`);
      }
    });

    // ---- Screen share consent flow ----

    // Child approves a pending screen share request
    socket.on("screen_share_accept", async ({ sessionId }: { sessionId: string }) => {
      if (role !== "CHILD") return;
      const session = await ScreenShareSession.findById(sessionId);
      if (!session || session.childId.toString() !== userId) return;

      // Always ensure the accepting socket and parent sockets are in the session room
      socket.join(`session:${sessionId}`);
      for (const parentSocketId of getParentSocketIds(session.parentId.toString())) {
        io.sockets.sockets.get(parentSocketId)?.join(`session:${sessionId}`);
      }

      if (session.status === "REQUESTED") {
        session.status = "ACCEPTED";
        await session.save();
        io.to(`session:${sessionId}`).emit("screen_share_accept", { sessionId });
      } else if (session.status === "ACCEPTED" || session.status === "ACTIVE") {
        // If re-accepting or service socket connected, inform room of acceptance
        io.to(`session:${sessionId}`).emit("screen_share_accept", { sessionId });
      }
    });

    // Child rejects a pending screen share request
    socket.on("screen_share_reject", async ({ sessionId }: { sessionId: string }) => {
      if (role !== "CHILD") return;
      const session = await ScreenShareSession.findById(sessionId);
      if (!session || session.childId.toString() !== userId) return;
      if (session.status !== "REQUESTED") return;

      session.status = "REJECTED";
      session.endedAt = new Date();
      session.endedBy = "CHILD";
      await session.save();

      for (const parentSocketId of getParentSocketIds(session.parentId.toString())) {
        io.to(parentSocketId).emit("screen_share_reject", { sessionId });
      }
    });

    // ---- Camera stream flow ----

    // Child accepts / starts camera stream
    socket.on("camera_stream_accept", async ({ sessionId }: { sessionId: string }) => {
      if (role !== "CHILD") return;
      const session = await CameraStreamSession.findById(sessionId);
      if (!session || session.childId.toString() !== userId) return;

      socket.join(`session:${sessionId}`);
      for (const parentSocketId of getParentSocketIds(session.parentId.toString())) {
        io.sockets.sockets.get(parentSocketId)?.join(`session:${sessionId}`);
      }

      if (session.status === "REQUESTED") {
        session.status = "ACCEPTED";
        await session.save();
        io.to(`session:${sessionId}`).emit("camera_stream_accept", { sessionId });
      } else if (session.status === "ACCEPTED" || session.status === "ACTIVE") {
        io.to(`session:${sessionId}`).emit("camera_stream_accept", { sessionId });
      }
    });

    // Child rejects or reports error for camera stream
    socket.on(
      "camera_stream_reject",
      async ({ sessionId, reason }: { sessionId: string; reason?: string }) => {
        if (role !== "CHILD") return;
        const session = await CameraStreamSession.findById(sessionId);
        if (!session || session.childId.toString() !== userId) return;
        if (session.status !== "REQUESTED") return;

        session.status = "REJECTED";
        session.endedAt = new Date();
        session.endedBy = "CHILD";
        await session.save();

        for (const parentSocketId of getParentSocketIds(session.parentId.toString())) {
          io.to(parentSocketId).emit("camera_stream_reject", { sessionId, reason });
        }
      }
    );

    // Parent requests switching camera lens (front / back)
    socket.on(
      "camera_stream_switch_camera",
      async ({ sessionId, cameraFacing }: { sessionId: string; cameraFacing?: "BACK" | "FRONT" }) => {
        if (role !== "PARENT") return;
        const session = await CameraStreamSession.findById(sessionId);
        if (!session || session.parentId.toString() !== userId) return;

        if (cameraFacing) {
          session.cameraFacing = cameraFacing;
          await session.save();
        }

        socket.to(`session:${sessionId}`).emit("camera_stream_switch_camera", {
          sessionId,
          cameraFacing: session.cameraFacing,
        });
      }
    );

    // Camera stream stopped over socket
    socket.on("camera_stream_stopped", async ({ sessionId }: { sessionId: string }) => {
      const session = await CameraStreamSession.findById(sessionId);
      if (!session) return;
      const isParticipant =
        (role === "PARENT" && session.parentId.toString() === userId) ||
        (role === "CHILD" && session.childId.toString() === userId);
      if (!isParticipant || session.status === "ENDED") return;

      session.status = "ENDED";
      session.endedAt = new Date();
      session.endedBy = role;
      await session.save();

      io.to(`session:${sessionId}`).emit("camera_stream_stopped", { sessionId, endedBy: role });
    });

    // ---- WebRTC signaling relay (backend never touches media, just forwards SDP/ICE) ----

    socket.on(
      "webrtc_offer",
      async ({ sessionId, sdp }: { sessionId: string; sdp: unknown }) => {
        const screenSession = await ScreenShareSession.findById(sessionId);
        if (screenSession) {
          if (screenSession.status === "ACCEPTED") {
            screenSession.status = "ACTIVE";
            screenSession.startedAt = new Date();
            await screenSession.save();
            io.to(`session:${sessionId}`).emit("screen_share_started", { sessionId });
          }
        } else {
          const cameraSession = await CameraStreamSession.findById(sessionId);
          if (cameraSession && cameraSession.status === "ACCEPTED") {
            cameraSession.status = "ACTIVE";
            cameraSession.startedAt = new Date();
            await cameraSession.save();
            io.to(`session:${sessionId}`).emit("camera_stream_started", { sessionId });
          }
        }
        socket.to(`session:${sessionId}`).emit("webrtc_offer", { sessionId, sdp });
      }
    );

    socket.on("webrtc_answer", ({ sessionId, sdp }: { sessionId: string; sdp: unknown }) => {
      socket.to(`session:${sessionId}`).emit("webrtc_answer", { sessionId, sdp });
    });

    socket.on(
      "ice_candidate",
      ({ sessionId, candidate }: { sessionId: string; candidate: unknown }) => {
        socket.to(`session:${sessionId}`).emit("ice_candidate", { sessionId, candidate });
      }
    );

    // Either side can signal a stop over the socket too (REST endpoint also supports this)
    socket.on("screen_share_stopped", async ({ sessionId }: { sessionId: string }) => {
      const session = await ScreenShareSession.findById(sessionId);
      if (!session) return;
      const isParticipant =
        (role === "PARENT" && session.parentId.toString() === userId) ||
        (role === "CHILD" && session.childId.toString() === userId);
      if (!isParticipant || session.status === "ENDED") return;

      session.status = "ENDED";
      session.endedAt = new Date();
      session.endedBy = role;
      await session.save();

      io.to(`session:${sessionId}`).emit("screen_share_stopped", { sessionId, endedBy: role });
    });

    // ---- Live GPS Location Tracking ----
    socket.on(
      "location_update",
      async (data: {
        latitude: number;
        longitude: number;
        accuracy?: number;
        altitude?: number;
        speed?: number;
        heading?: number;
        batteryLevel?: number;
        recordedAt?: string | Date;
      }) => {
        if (role !== "CHILD" || !data || typeof data.latitude !== "number" || typeof data.longitude !== "number") {
          return;
        }

        try {
          const recordedDate = data.recordedAt ? new Date(data.recordedAt) : new Date();
          const device = await Device.findOne({ childId: userId }).sort({ updatedAt: -1 });

          const locationPayload = {
            latitude: data.latitude,
            longitude: data.longitude,
            accuracy: data.accuracy,
            altitude: data.altitude,
            speed: data.speed,
            heading: data.heading,
            batteryLevel: data.batteryLevel,
            recordedAt: recordedDate,
          };

          await LocationRecord.create({
            childId: userId,
            deviceId: device?._id || null,
            ...locationPayload,
          });

          if (device) {
            device.lastLocation = locationPayload;
            device.lastSeen = new Date();
            await device.save();
          }

          const child = await User.findById(userId);
          if (child?.parentId) {
            const parentSocketIds = getParentSocketIds(child.parentId.toString());
            for (const pSocketId of parentSocketIds) {
              io.to(pSocketId).emit("child_location_update", {
                childId: userId,
                ...locationPayload,
              });
            }

            // Real-time boundary evaluation against active geofences
            evaluateChildGeofences(userId, child.parentId.toString(), locationPayload).catch((err) =>
              console.error("Error in evaluateChildGeofences (socket):", err)
            );
          }
        } catch (err) {
          // Keep socket resilient on DB write error
          console.error("Failed to process location_update socket event:", err);
        }
      }
    );

    // ---- App & Game Blocker: Unblock Request flow ----
    socket.on(
      "unblock_request",
      async (data: {
        requestId?: string;
        childId?: string;
        packageName: string;
        appName: string;
        reason?: string;
      }) => {
        if (role !== "CHILD" || !data.packageName) return;
        try {
          const child = await User.findById(userId);
          if (child?.parentId) {
            const parentSockets = getParentSocketIds(child.parentId.toString());
            const payload = {
              requestId: data.requestId || new Date().getTime().toString(),
              childId: userId,
              childName: child.name,
              packageName: data.packageName,
              appName: data.appName,
              reason: data.reason || "Need extra time",
              requestedAt: new Date().toISOString(),
            };
            for (const pSocketId of parentSockets) {
              io.to(pSocketId).emit("unblock_request", payload);
            }
          }
        } catch (err) {
          console.error("Error processing unblock_request socket event:", err);
        }
      }
    );

    // Parent responds to child's unblock request
    socket.on(
      "unblock_response",
      async (data: {
        requestId: string;
        childId: string;
        packageName: string;
        approved: boolean;
        temporaryDurationMinutes?: number;
      }) => {
        if (role !== "PARENT" || !data.childId || !data.packageName) return;
        try {
          const childSockets = getChildSocketIds(data.childId);
          for (const cSocketId of childSockets) {
            io.to(cSocketId).emit("unblock_response", {
              requestId: data.requestId,
              packageName: data.packageName,
              approved: data.approved,
              temporaryDurationMinutes: data.temporaryDurationMinutes ?? (data.approved ? 15 : 0),
            });
          }
        } catch (err) {
          console.error("Error processing unblock_response socket event:", err);
        }
      }
    );

    // Parent toggles instant lockdown over socket
    socket.on(
      "instant_lockdown_toggle",
      async (data: { childId: string; isPaused: boolean }) => {
        if (role !== "PARENT" || !data.childId) return;
        try {
          await Device.updateMany({ childId: data.childId }, { isPaused: data.isPaused });
          const childSockets = getChildSocketIds(data.childId);
          for (const cSocketId of childSockets) {
            io.to(cSocketId).emit("instant_lockdown_toggle", {
              isPaused: data.isPaused,
            });
          }
        } catch (err) {
          console.error("Error processing instant_lockdown_toggle socket event:", err);
        }
      }
    );

    // ---- Browsing History Monitoring: Real-time event ----
    socket.on(
      "new_browsing_activity",
      async (data: {
        url: string;
        domain: string;
        title?: string;
        browser?: string;
        isIncognito?: boolean;
        category?: string;
        isBlockedAttempt?: boolean;
        blockedReason?: string;
        visitedAt?: string | Date;
      }) => {
        if (role !== "CHILD" || !data.url || !data.domain) return;
        try {
          const device = await Device.findOne({ childId: userId }).sort({ updatedAt: -1 }).lean();
          const record = await BrowsingHistoryRecord.create({
            childId: userId,
            deviceId: device?._id ?? null,
            url: data.url,
            domain: data.domain,
            title: data.title || "",
            browser: (data.browser as any) || "OTHER",
            isIncognito: data.isIncognito ?? false,
            category: (data.category as any) || "GENERAL",
            isBlockedAttempt: data.isBlockedAttempt ?? false,
            blockedReason: data.blockedReason,
            visitedAt: data.visitedAt ? new Date(data.visitedAt) : new Date(),
          });

          const child = await User.findById(userId);
          if (child?.parentId) {
            const parentSockets = getParentSocketIds(child.parentId.toString());
            for (const pSocketId of parentSockets) {
              io.to(pSocketId).emit("new_browsing_activity", {
                childId: userId,
                record,
              });

              if (record.isBlockedAttempt || record.category === "ADULT" || record.category === "SUSPICIOUS") {
                io.to(pSocketId).emit("suspicious_web_alert", {
                  childId: userId,
                  childName: child.name,
                  record,
                });
              }
            }
          }
        } catch (err) {
          console.error("Error processing new_browsing_activity socket event:", err);
        }
      }
    );

    socket.on("disconnect", async () => {
      if (role === "CHILD") {
        const childId = findChildIdBySocket(socket.id);
        if (childId) {
          const isNowOffline = removeChildSocket(childId, socket.id);
          if (isNowOffline) {
            await Device.findOneAndUpdate(
              { childId },
              { status: "OFFLINE", lastSeen: new Date(), socketId: null },
              { sort: { updatedAt: -1 } }
            );
            socket.broadcast.emit("child_status_changed", { childId, status: "OFFLINE" });

            // Auto-end any still-active screen sessions for this child so the parent UI doesn't hang.
            const activeScreenSessions = await ScreenShareSession.find({
              childId,
              status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] },
            });
            for (const s of activeScreenSessions) {
              s.status = "ENDED";
              s.endedAt = new Date();
              s.endedBy = "SYSTEM";
              await s.save();
              io.to(`session:${s.id}`).emit("screen_share_stopped", {
                sessionId: s.id,
                endedBy: "SYSTEM",
                reason: "child_disconnected",
              });
            }

            // Auto-end any still-active camera sessions for this child
            const activeCameraSessions = await CameraStreamSession.find({
              childId,
              status: { $in: ["REQUESTED", "ACCEPTED", "ACTIVE"] },
            });
            for (const s of activeCameraSessions) {
              s.status = "ENDED";
              s.endedAt = new Date();
              s.endedBy = "SYSTEM";
              await s.save();
              io.to(`session:${s.id}`).emit("camera_stream_stopped", {
                sessionId: s.id,
                endedBy: "SYSTEM",
                reason: "child_disconnected",
              });
            }
          }
        }
      } else if (role === "PARENT") {
        removeParentSocket(userId, socket.id);
      }
    });
  });
}
