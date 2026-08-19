import { Response } from "express";
import { ScreenShareSession } from "../models/ScreenShareSession";
import { Device } from "../models/Device";
import { asyncHandler, AppError } from "../utils/http";
import { screenShareRequestSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { getIO } from "../socket/io";
import { getChildSocketId } from "../socket/presence";

// POST /api/screen-share/request (parent only)
export const requestScreenShare = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = screenShareRequestSchema.parse(req.body);
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) throw new AppError("Child has no registered device", 404);

  const childSocketId = getChildSocketId(childId);
  if (device.status !== "ONLINE" || !childSocketId) {
    throw new AppError("Child device is offline", 409);
  }

  const session = await ScreenShareSession.create({
    parentId,
    childId,
    deviceId: device.id,
    status: "REQUESTED",
    requestedAt: new Date(),
  });

  // Notify the child app over its socket
  getIO().to(childSocketId).emit("screen_share_request", {
    sessionId: session.id,
    parentId,
  });

  res.status(201).json({
    sessionId: session.id,
    status: session.status,
  });
});

// GET /api/screen-share/:id
export const getScreenShareSession = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const session = await ScreenShareSession.findById(req.params.id);
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
    requestedAt: session.requestedAt,
    startedAt: session.startedAt,
    endedAt: session.endedAt,
  });
});

// POST /api/screen-share/:id/stop (parent or child, must be a participant)
export const stopScreenShare = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const session = await ScreenShareSession.findById(req.params.id);
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
  getIO().to(`session:${session.id}`).emit("screen_share_stopped", {
    sessionId: session.id,
    endedBy: role,
  });

  res.json({ id: session.id, status: session.status });
});
