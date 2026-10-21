import { Schema, model, Types, Document } from "mongoose";

export type SafetySeverity = "CRITICAL" | "HIGH" | "MEDIUM";
export type SafetyAlertType =
  | "EXPLICIT_SCREEN_CONTENT"
  | "EXPLICIT_PHOTO_SAVED"
  | "ADULT_CONTENT_DETECTED";

export interface ISafetyAlert extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  externalId: string;
  alertType: SafetyAlertType;
  packageName?: string | null;
  appName?: string | null;
  confidenceScore: number;
  severity: SafetySeverity;
  isAcknowledged: boolean;
  acknowledgedAt?: Date | null;
  timestamp: Date;
  createdAt: Date;
}

const safetyAlertSchema = new Schema<ISafetyAlert>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true, index: true },
    externalId: { type: String, required: true },
    alertType: {
      type: String,
      enum: ["EXPLICIT_SCREEN_CONTENT", "EXPLICIT_PHOTO_SAVED", "ADULT_CONTENT_DETECTED"],
      required: true,
    },
    packageName: { type: String, default: null },
    appName: { type: String, default: null },
    confidenceScore: { type: Number, required: true, min: 0, max: 1 },
    severity: {
      type: String,
      enum: ["CRITICAL", "HIGH", "MEDIUM"],
      default: "CRITICAL",
    },
    isAcknowledged: { type: Boolean, default: false },
    acknowledgedAt: { type: Date, default: null },
    timestamp: { type: Date, required: true, index: true },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

safetyAlertSchema.index({ childId: 1, externalId: 1 }, { unique: true });
safetyAlertSchema.index({ childId: 1, isAcknowledged: 1 });
safetyAlertSchema.index({ childId: 1, timestamp: -1 });

export const SafetyAlert = model<ISafetyAlert>("SafetyAlert", safetyAlertSchema);
