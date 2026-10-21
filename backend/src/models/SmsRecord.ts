import { Schema, model, Types, Document } from "mongoose";

export type SmsDirection = "INCOMING" | "OUTGOING" | "UNKNOWN";

export interface ISmsRecord extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  externalId: string;
  phoneNumber?: string | null;
  contactName?: string | null;
  direction: SmsDirection;
  body?: string | null;
  hasBody: boolean;
  timestamp: Date;
  createdAt: Date;
}

const smsRecordSchema = new Schema<ISmsRecord>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true, index: true },
    externalId: { type: String, required: true },
    phoneNumber: { type: String, default: null },
    contactName: { type: String, default: null },
    direction: {
      type: String,
      enum: ["INCOMING", "OUTGOING", "UNKNOWN"],
      default: "UNKNOWN",
    },
    body: { type: String, default: null },
    hasBody: { type: Boolean, default: false },
    timestamp: { type: Date, required: true, index: true },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

// Unique compound index on childId and externalId to guarantee idempotent sync without duplicate records
smsRecordSchema.index({ childId: 1, externalId: 1 }, { unique: true });
smsRecordSchema.index({ childId: 1, timestamp: -1 });

export const SmsRecord = model<ISmsRecord>("SmsRecord", smsRecordSchema);
