import { Schema, model } from "mongoose";
const schema = new Schema({
  _id: { type: String, required: true }, childId: { type: Schema.Types.ObjectId, required: true },
  kind: { type: String, enum: ["NOTIFICATION", "CALL", "SMS", "SAFETY"], required: true },
  eventId: { type: String, required: true }, eventAt: { type: Date, required: true }, syncedAt: { type: Date, default: Date.now },
  packageName: String, eventType: String, direction: String, durationSeconds: Number,
  identifierHash: String, maskedIdentifier: String, subscriptionId: String,
  mediaType: String, category: String, confidence: Number, modelVersion: String,
  reviewStatus: { type: String, enum: ["NEW", "CONFIRMED", "DISMISSED"], default: "NEW" },
  expiresAt: { type: Date, required: true },
}, { strict: "throw" });
schema.index({ childId: 1, kind: 1, eventAt: -1 });
schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
export const ActivityEvent = model("ActivityEvent", schema);
