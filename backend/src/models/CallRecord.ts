import { Schema, model, Types, Document } from "mongoose";

export type CallDirection = "INCOMING" | "OUTGOING" | "MISSED" | "REJECTED" | "UNKNOWN";

export interface ICallRecord extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  externalId: string;
  phoneNumber?: string | null;
  contactName?: string | null;
  direction: CallDirection;
  durationSeconds: number;
  timestamp: Date;
  createdAt: Date;
}

const callRecordSchema = new Schema<ICallRecord>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true, index: true },
    externalId: { type: String, required: true },
    phoneNumber: { type: String, default: null },
    contactName: { type: String, default: null },
    direction: {
      type: String,
      enum: ["INCOMING", "OUTGOING", "MISSED", "REJECTED", "UNKNOWN"],
      default: "UNKNOWN",
    },
    durationSeconds: { type: Number, default: 0 },
    timestamp: { type: Date, required: true, index: true },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

// Unique compound index on childId and externalId to guarantee idempotent sync without duplicate records
callRecordSchema.index({ childId: 1, externalId: 1 }, { unique: true });
callRecordSchema.index({ childId: 1, timestamp: -1 });

export const CallRecord = model<ICallRecord>("CallRecord", callRecordSchema);
