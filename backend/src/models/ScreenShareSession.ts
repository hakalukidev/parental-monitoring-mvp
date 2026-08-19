import { Schema, model, Types, Document } from "mongoose";

export type ScreenShareStatus =
  | "REQUESTED"
  | "ACCEPTED"
  | "REJECTED"
  | "ACTIVE"
  | "ENDED"
  | "FAILED";

export interface IScreenShareSession extends Document {
  _id: Types.ObjectId;
  parentId: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  status: ScreenShareStatus;
  requestedAt: Date;
  startedAt?: Date | null;
  endedAt?: Date | null;
  endedBy?: "PARENT" | "CHILD" | "SYSTEM" | null;
}

const screenShareSessionSchema = new Schema<IScreenShareSession>({
  parentId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
  childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
  deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true },
  status: {
    type: String,
    enum: ["REQUESTED", "ACCEPTED", "REJECTED", "ACTIVE", "ENDED", "FAILED"],
    default: "REQUESTED",
  },
  requestedAt: { type: Date, default: Date.now },
  startedAt: { type: Date, default: null },
  endedAt: { type: Date, default: null },
  endedBy: { type: String, enum: ["PARENT", "CHILD", "SYSTEM", null], default: null },
});

export const ScreenShareSession = model<IScreenShareSession>(
  "ScreenShareSession",
  screenShareSessionSchema
);
