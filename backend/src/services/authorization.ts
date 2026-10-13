import { z } from "zod";
import { User } from "../models/User";
import { AppError } from "../utils/http";

export const objectIdSchema = z.string().regex(/^[a-f\d]{24}$/i, "Invalid identifier");
export interface Actor { userId: string; role: "PARENT" | "CHILD" }

export async function ownedChild(actor: Actor, childId: string) {
  objectIdSchema.parse(childId);
  if (actor.role !== "PARENT") throw new AppError("Forbidden", 403);
  const child = await User.findOne({ _id: childId, role: "CHILD", parentId: actor.userId });
  if (!child) throw new AppError("Child not found or not owned by this parent", 403);
  return child;
}

export interface SessionIdentity {
  parentId: { toString(): string }; childId: { toString(): string };
  status: string; requestedAt: Date; startedAt?: Date | null;
}
export const openSessionStates = ["REQUESTED", "ACCEPTED", "ACTIVE"];
export function sessionExpired(session: SessionIdentity, now = Date.now()): boolean {
  const start = session.status === "ACTIVE" ? session.startedAt?.getTime() ?? session.requestedAt.getTime() : session.requestedAt.getTime();
  const duration = session.status === "ACTIVE" ? 30 * 60_000 : 2 * 60_000;
  return !Number.isFinite(start) || now - start >= duration;
}
export function assertSessionParticipant(actor: Actor, session: SessionIdentity, states?: readonly string[]): void {
  const participant = actor.role === "PARENT"
    ? session.parentId.toString() === actor.userId
    : session.childId.toString() === actor.userId;
  if (!participant) throw new AppError("Forbidden", 403);
  if (states && (!states.includes(session.status) || sessionExpired(session))) {
    throw new AppError("Session is unavailable or expired", 409);
  }
}
