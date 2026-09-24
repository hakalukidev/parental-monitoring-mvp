import { Schema, model, Types, Document } from "mongoose";

export interface IGeofenceEvent extends Document {
  _id: Types.ObjectId;
  parentId: Types.ObjectId;
  childId: Types.ObjectId;
  geofenceId: Types.ObjectId;
  geofenceName: string;
  eventType: "EXIT" | "ENTRY";
  zoneType: "SAFE_ZONE" | "RESTRICTED_ZONE";
  latitude: number;
  longitude: number;
  accuracy?: number;
  speed?: number;
  distanceFromCenter: number;
  geofenceRadius: number;
  address?: string;
  isRead: boolean;
  triggeredAt: Date;
  createdAt: Date;
}

const geofenceEventSchema = new Schema<IGeofenceEvent>(
  {
    parentId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    geofenceId: { type: Schema.Types.ObjectId, ref: "Geofence", required: true, index: true },
    geofenceName: { type: String, required: true },
    eventType: { type: String, enum: ["EXIT", "ENTRY"], required: true },
    zoneType: { type: String, enum: ["SAFE_ZONE", "RESTRICTED_ZONE"], required: true },
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
    accuracy: { type: Number, default: null },
    speed: { type: Number, default: null },
    distanceFromCenter: { type: Number, required: true },
    geofenceRadius: { type: Number, required: true },
    address: { type: String, default: "" },
    isRead: { type: Boolean, default: false, index: true },
    triggeredAt: { type: Date, required: true, default: Date.now, index: true },
  },
  { timestamps: true }
);

geofenceEventSchema.index({ childId: 1, triggeredAt: -1 });
geofenceEventSchema.index({ parentId: 1, isRead: 1 });

export const GeofenceEvent = model<IGeofenceEvent>("GeofenceEvent", geofenceEventSchema);
