import { Response } from "express";
import { z } from "zod";
import { AuthedRequest } from "../middleware/auth";
import { asyncHandler, AppError } from "../utils/http";
import { AudioSession } from "../models/AudioSession";
import { Device } from "../models/Device";
import { ownedChild, objectIdSchema, assertSessionParticipant, openSessionStates, sessionExpired } from "../services/authorization";
import { featureEnabled } from "../services/features";
import { reserveMediaSession, releaseMediaSession, notifySessionEnd } from "../services/mediaSessions";
import { getIO } from "../socket/io";
import { getChildSocketIds, getParentSocketIds } from "../socket/presence";

export const requestAudioSession = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = z.object({ childId: objectIdSchema }).parse(req.body);
  const parentId = req.user!.id;
  await ownedChild({ userId: parentId, role: req.user!.role }, childId);
  if (!featureEnabled("AUDIO")) throw new AppError("Audio check-in is not enabled on this server", 503);
  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device || device.mediaConsentVersion !== 2 || device.audioCheckInVersion !== 1) throw new AppError("Update the child app to enable audio check-in", 409);
  const children = getChildSocketIds(childId);
  if (!children.length) throw new AppError("Child device is offline", 409);
  const id = await reserveMediaSession("audio", childId);
  try {
    await reserveMediaSession("microphone", childId, id);
    const session = await AudioSession.create({ _id: id, parentId, childId, deviceId: device.id });
    for (const socketId of getParentSocketIds(parentId)) getIO().sockets.sockets.get(socketId)?.join(`session:${id}`);
    getIO().to(children).emit("audio_session_request", { sessionId: session.id, requestedAt: session.requestedAt });
    res.status(201).json({ sessionId: session.id, status: session.status });
  } catch (error) { await releaseMediaSession(id.toString()); throw error; }
});

export const getAudioSession = asyncHandler(async (req: AuthedRequest, res: Response) => {
  objectIdSchema.parse(req.params.id);
  const session = await AudioSession.findById(req.params.id);
  if (!session) throw new AppError("Session not found", 404);
  assertSessionParticipant({ userId: req.user!.id, role: req.user!.role }, session);
  res.json({ id: session.id, status: sessionExpired(session) && openSessionStates.includes(session.status) ? "ENDED" : session.status, requestedAt: session.requestedAt, startedAt: session.startedAt, endedAt: session.endedAt });
});

export const stopAudioSession = asyncHandler(async (req: AuthedRequest, res: Response) => {
  objectIdSchema.parse(req.params.id);
  const session = await AudioSession.findById(req.params.id);
  if (!session) throw new AppError("Session not found", 404);
  assertSessionParticipant({ userId: req.user!.id, role: req.user!.role }, session);
  await ownedChild({ userId: session.parentId.toString(), role: "PARENT" }, session.childId.toString());
  if (openSessionStates.includes(session.status)) {
    await AudioSession.updateOne({ _id: session._id, status: { $in: openSessionStates } }, { $set: { status: "ENDED", endedAt: new Date(), endedBy: req.user!.role } });
    await releaseMediaSession(session.id);
    notifySessionEnd(session, "audio_session_stopped", req.user!.role);
  }
  res.json({ id: session.id, status: "ENDED" });
});
