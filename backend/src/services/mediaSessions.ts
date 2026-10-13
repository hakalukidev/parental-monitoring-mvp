import { Types } from "mongoose";
import { MediaLease } from "../models/MediaLease";
import { AppError } from "../utils/http";
import { getIO } from "../socket/io";
import { getChildSocketIds, getParentSocketIds } from "../socket/presence";

export async function reserveMediaSession(kind: string, childId: string): Promise<Types.ObjectId> {
  const id = new Types.ObjectId();
  try {
    await MediaLease.findOneAndUpdate({ _id: `${kind}:${childId}`, expiresAt: { $lte: new Date() } }, { $set: { sessionId: id, expiresAt: new Date(Date.now() + 120_000) } }, { upsert: true, new: true });
    return id;
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === 11000) throw new AppError("A check-in for this child is already pending or active", 409);
    throw error;
  }
}
export async function releaseMediaSession(id: string): Promise<void> {
  await MediaLease.deleteMany({ sessionId: id });
}
export function notifySessionEnd(session: { _id: { toString(): string }; parentId: { toString(): string }; childId: { toString(): string } }, event: string, endedBy: string, reason?: string): void {
  const id = session._id.toString();
  const io = getIO();
  const rooms = [`session:${id}`, ...getParentSocketIds(session.parentId.toString()), ...getChildSocketIds(session.childId.toString())];
  io.to(rooms).emit(event, { sessionId: id, endedBy, reason });
  io.in(`session:${id}`).socketsLeave(`session:${id}`);
}
