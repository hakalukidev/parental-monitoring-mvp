import { Schema, model, Types, Document } from "mongoose";

export type CameraStreamStatus =
  | "REQUESTED"
  | "ACCEPTED"
  | "REJECTED"
  | "ACTIVE"
  | "ENDED"
  | "FAILED";

export type CameraFacing = "BACK" | "FRONT";

export interface ICameraStreamSession extends Document {
  _id: Types.ObjectId;
  parentId: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  cameraFacing: CameraFacing;
  withAudio: boolean;
  status: CameraStreamStatus;
  requestedAt: Date;
  startedAt?: Date | null;
  endedAt?: Date | null;
  endedBy?: "PARENT" | "CHILD" | "SYSTEM" | null;
}

const cameraStreamSessionSchema = new Schema<ICameraStreamSession>({
  parentId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
  childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
  deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true },
  cameraFacing: { type: String, enum: ["BACK", "FRONT"], default: "BACK" },
  withAudio: { type: Boolean, default: true },
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

export const CameraStreamSession = model<ICameraStreamSession>(
  "CameraStreamSession",
  cameraStreamSessionSchema
);
