import { Schema, model, Types, Document } from "mongoose";

export interface ILocationRecord extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId?: Types.ObjectId;
  latitude: number;
  longitude: number;
  accuracy?: number; // in meters
  altitude?: number; // in meters
  speed?: number; // in m/s
  heading?: number; // 0 - 360 degrees
  batteryLevel?: number; // 0 - 100 percentage
  recordedAt: Date; // GPS timestamp on device
  createdAt: Date;
  updatedAt: Date;
}

const locationRecordSchema = new Schema<ILocationRecord>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", default: null, index: true },
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
    accuracy: { type: Number, default: null },
    altitude: { type: Number, default: null },
    speed: { type: Number, default: null },
    heading: { type: Number, default: null },
    batteryLevel: { type: Number, default: null },
    recordedAt: { type: Date, required: true, default: Date.now, index: true },
  },
  { timestamps: true }
);

// Compound index for efficient breadcrumb trail queries by child and time range
locationRecordSchema.index({ childId: 1, recordedAt: -1 });
locationRecordSchema.index({ childId: 1, createdAt: -1 });

export const LocationRecord = model<ILocationRecord>("LocationRecord", locationRecordSchema);
