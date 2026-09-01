import { Response } from "express";
import { CameraStreamSession } from "../models/CameraStreamSession";
import { Device } from "../models/Device";
import { asyncHandler, AppError } from "../utils/http";
import { cameraStreamRequestSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getChildSocketIds, getParentSocketIds } from "../socket/presence";

// POST /api/camera-stream/request (parent only)
export const requestCameraStream = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId, cameraFacing, withAudio } = cameraStreamRequestSchema.parse(req.body);
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) throw new AppError("Child has no registered device", 404);

  const childSocketIds = getChildSocketIds(childId);
  if (device.status !== "ONLINE" || childSocketIds.length === 0) {
    throw new AppError("Child device is offline", 409);
  }

  const session = await CameraStreamSession.create({
    parentId,
    childId,
    deviceId: device.id,
    cameraFacing,
    withAudio,
    status: "REQUESTED",
    requestedAt: new Date(),
  });

  // Pre-join all active parent sockets to the session room immediately
  for (const pId of getParentSocketIds(parentId)) {
    getIO().sockets.sockets.get(pId)?.join(`session:${session.id}`);
  }

  // Notify the child app over all its active sockets
  for (const sId of childSocketIds) {
    getIO().to(sId).emit("camera_stream_request", {
      sessionId: session.id,
      parentId,
      cameraFacing,
      withAudio,
    });
  }

  res.status(201).json({
    sessionId: session.id,
    status: session.status,
    cameraFacing: session.cameraFacing,
    withAudio: session.withAudio,
  });
});

// GET /api/camera-stream/:id
export const getCameraStreamSession = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const session = await CameraStreamSession.findById(req.params.id);
  if (!session) throw new AppError("Session not found", 404);

  const userId = req.user!.id;
  const role = req.user!.role;
  const isOwner =
    (role === "PARENT" && session.parentId.toString() === userId) ||
    (role === "CHILD" && session.childId.toString() === userId);
  if (!isOwner) throw new AppError("Forbidden", 403);

  res.json({
    id: session.id,
    status: session.status,
    cameraFacing: session.cameraFacing,
    withAudio: session.withAudio,
    requestedAt: session.requestedAt,
    startedAt: session.startedAt,
    endedAt: session.endedAt,
  });
});

// POST /api/camera-stream/:id/stop (parent or child, must be a participant)
export const stopCameraStream = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const session = await CameraStreamSession.findById(req.params.id);
  if (!session) throw new AppError("Session not found", 404);

  const userId = req.user!.id;
  const role = req.user!.role;
  const isParentParticipant = role === "PARENT" && session.parentId.toString() === userId;
  const isChildParticipant = role === "CHILD" && session.childId.toString() === userId;
  if (!isParentParticipant && !isChildParticipant) throw new AppError("Forbidden", 403);

  if (session.status === "ENDED") {
    res.json({ id: session.id, status: session.status });
    return;
  }

  session.status = "ENDED";
  session.endedAt = new Date();
  session.endedBy = role;
  await session.save();

  // Notify the room so both sides tear down WebRTC + UI state
  getIO().to(`session:${session.id}`).emit("camera_stream_stopped", {
    sessionId: session.id,
    endedBy: role,
  });

  res.json({ id: session.id, status: session.status });
});
