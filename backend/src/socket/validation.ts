import { z } from "zod";
import { objectIdSchema } from "../services/authorization";

export const sessionPayload = z.object({ sessionId: objectIdSchema });
export const childPayload = z.object({ childId: objectIdSchema });
export const heartbeatPayload = z.object({
  batteryLevel: z.number().finite().min(0).max(100).optional(),
  isGpsOn: z.boolean().optional(), deviceName: z.string().trim().min(1).max(100).optional(),
});
export const sdpPayload = sessionPayload.extend({ sdp: z.object({
  type: z.enum(["offer", "answer"]), sdp: z.string().min(1).max(65_536),
}) });
export const icePayload = sessionPayload.extend({ candidate: z.object({
  candidate: z.string().max(4096), sdpMid: z.string().max(100).nullable().optional(),
  sdpMLineIndex: z.number().int().min(0).max(100).nullable().optional(),
}) });
export const unblockRequestPayload = z.object({
  requestId: z.string().min(1).max(100), packageName: z.string().min(1).max(255),
  appName: z.string().min(1).max(100), reason: z.string().max(500).default("Need extra time"),
});
export const unblockResponsePayload = childPayload.extend({
  requestId: z.string().min(1).max(100), packageName: z.string().min(1).max(255),
  approved: z.boolean(), temporaryDurationMinutes: z.number().int().min(1).max(120).optional(),
});

export class EventBudget {
  private started = Date.now();
  private count = 0;
  take(now = Date.now()): boolean {
    if (now - this.started >= 10_000) { this.started = now; this.count = 0; }
    return ++this.count <= 120;
  }
}
