import { Schema, model, Types, Document } from "mongoose";

export type GeofenceTriggerType = "EXIT" | "ENTRY" | "BOTH";
export type GeofenceZoneType = "SAFE_ZONE" | "RESTRICTED_ZONE";
export type GeofenceState = "INSIDE" | "OUTSIDE" | "UNKNOWN";

export interface IGeofence extends Document {
  _id: Types.ObjectId;
  parentId: Types.ObjectId;
  childId: Types.ObjectId;
  name: string;
  latitude: number;
  longitude: number;
  radius: number; // Radius in meters (min 30m, max 20000m)
  address?: string;
  zoneType: GeofenceZoneType;
  triggerType: GeofenceTriggerType;
  isEnabled: boolean;
  colorHex?: string;
  lastState: GeofenceState;
  lastStateChangedAt?: Date;
  lastTriggeredAt?: Date;
  schedule?: {
    daysOfWeek: number[]; // 0 = Sun, 1 = Mon ... 6 = Sat
    startTime?: string; // "08:00"
    endTime?: string; // "15:00"
  };
  createdAt: Date;
  updatedAt: Date;
}

const geofenceSchema = new Schema<IGeofence>(
  {
    parentId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 100 },
    latitude: { type: Number, required: true, min: -90, max: 90 },
    longitude: { type: Number, required: true, min: -180, max: 180 },
    radius: { type: Number, required: true, min: 30, max: 20000, default: 200 },
    address: { type: String, default: "" },
    zoneType: { type: String, enum: ["SAFE_ZONE", "RESTRICTED_ZONE"], default: "SAFE_ZONE" },
    triggerType: { type: String, enum: ["EXIT", "ENTRY", "BOTH"], default: "EXIT" },
    isEnabled: { type: Boolean, default: true, index: true },
    colorHex: { type: String, default: "#2196F3" },
    lastState: { type: String, enum: ["INSIDE", "OUTSIDE", "UNKNOWN"], default: "UNKNOWN" },
    lastStateChangedAt: { type: Date, default: null },
    lastTriggeredAt: { type: Date, default: null },
    schedule: {
      daysOfWeek: { type: [Number], default: [0, 1, 2, 3, 4, 5, 6] },
      startTime: { type: String, default: null },
      endTime: { type: String, default: null },
    },
  },
  { timestamps: true }
);

geofenceSchema.index({ childId: 1, isEnabled: 1 });
geofenceSchema.index({ parentId: 1, childId: 1 });

export const Geofence = model<IGeofence>("Geofence", geofenceSchema);
