import { Schema, model } from "mongoose";
const schema = new Schema({
  _id: { type: String, required: true },
  notificationAccess: { type: String, default: "UNKNOWN" },
  callLogAccess: { type: String, default: "UNKNOWN" }, smsAccess: { type: String, default: "UNKNOWN" },
  safetyModel: { type: String, default: "UNAVAILABLE" }, sourceCoverage: { type: String, default: "SELECTED_MEDIA_ONLY" },
  listenerConnected: { type: Boolean, default: false }, queuedEvents: { type: Number, default: 0 }, droppedEvents: { type: Number, default: 0 },
  lastSyncedAt: { type: Date, default: null }, updatedAt: { type: Date, default: Date.now },
});
export const ActivityCapability = model("ActivityCapability", schema);
