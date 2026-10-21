import { Schema, model, Document, Types } from "mongoose";

export type AudioStreamStatus =
  | "REQUESTED"
  | "ACCEPTED"
  | "REJECTED"
  | "ACTIVE"
  | "ENDED"
  | "FAILED";

export interface IAudioStreamSession extends Document {
  parentId: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  status: AudioStreamStatus;
  requestedAt: Date;
  startedAt?: Date | null;
  endedAt?: Date | null;
  endedBy?: "PARENT" | "CHILD" | "SYSTEM" | null;
  createdAt: Date;
  updatedAt: Date;
}

const AudioStreamSessionSchema = new Schema<IAudioStreamSession>(
  {
    parentId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true },
    status: {
      type: String,
      enum: ["REQUESTED", "ACCEPTED", "REJECTED", "ACTIVE", "ENDED", "FAILED"],
      default: "REQUESTED",
      index: true,
    },

    requestedAt: { type: Date, default: Date.now },
    startedAt: { type: Date },
    endedAt: { type: Date },
    endedBy: { type: String, enum: ["PARENT", "CHILD", "SYSTEM"] },
  },
  { timestamps: true }
);

export const AudioStreamSession = model<IAudioStreamSession>(
  "AudioStreamSession",
  AudioStreamSessionSchema
);
