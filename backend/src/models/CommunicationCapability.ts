import { Schema, model, Types, Document } from "mongoose";

export type CapabilityStatus =
  | "AVAILABLE"
  | "PERMISSION_REQUIRED"
  | "PERMISSION_DENIED"
  | "RESTRICTED_BY_OS"
  | "DISABLED"
  | "UNSUPPORTED";

export interface ICommunicationCapability extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId?: Types.ObjectId | null;
  callsStatus: CapabilityStatus;
  smsMetadataStatus: CapabilityStatus;
  smsContentStatus: CapabilityStatus;
  updatedAt: Date;
}

const communicationCapabilitySchema = new Schema<ICommunicationCapability>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, unique: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", default: null },
    callsStatus: {
      type: String,
      enum: ["AVAILABLE", "PERMISSION_REQUIRED", "PERMISSION_DENIED", "RESTRICTED_BY_OS", "DISABLED", "UNSUPPORTED"],
      default: "PERMISSION_REQUIRED",
    },
    smsMetadataStatus: {
      type: String,
      enum: ["AVAILABLE", "PERMISSION_REQUIRED", "PERMISSION_DENIED", "RESTRICTED_BY_OS", "DISABLED", "UNSUPPORTED"],
      default: "PERMISSION_REQUIRED",
    },
    smsContentStatus: {
      type: String,
      enum: ["AVAILABLE", "PERMISSION_REQUIRED", "PERMISSION_DENIED", "RESTRICTED_BY_OS", "DISABLED", "UNSUPPORTED"],
      default: "PERMISSION_REQUIRED",
    },
  },
  {
    timestamps: { createdAt: false, updatedAt: true },
  }
);

export const CommunicationCapability = model<ICommunicationCapability>(
  "CommunicationCapability",
  communicationCapabilitySchema
);
