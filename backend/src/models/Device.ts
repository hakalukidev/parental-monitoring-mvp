import { Schema, model, Types, Document } from "mongoose";

export type DeviceStatus = "ONLINE" | "OFFLINE";

export interface IDevice extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceName: string;
  platform: string; // e.g. "Android"
  status: DeviceStatus;
  lastSeen: Date;
  socketId?: string | null; // current active socket connection id, if online
  createdAt: Date;
  updatedAt: Date;
}

const deviceSchema = new Schema<IDevice>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceName: { type: String, required: true },
    platform: { type: String, default: "Android" },
    status: { type: String, enum: ["ONLINE", "OFFLINE"], default: "OFFLINE" },
    lastSeen: { type: Date, default: Date.now },
    socketId: { type: String, default: null },
  },
  { timestamps: true }
);

export const Device = model<IDevice>("Device", deviceSchema);
