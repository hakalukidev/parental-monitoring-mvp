import { Schema, model, Types, Document } from "mongoose";

export interface INotificationRecord extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId: Types.ObjectId;
  externalId: string;
  packageName: string;
  appName: string;
  title: string;
  content: string;
  subText?: string | null;
  postTime: Date;
  createdAt: Date;
}

const notificationRecordSchema = new Schema<INotificationRecord>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", required: true, index: true },
    externalId: { type: String, required: true },
    packageName: { type: String, required: true, index: true },
    appName: { type: String, required: true },
    title: { type: String, default: "" },
    content: { type: String, default: "" },
    subText: { type: String, default: null },
    postTime: { type: Date, required: true, index: true },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

// Idempotent upsert indexing
notificationRecordSchema.index({ childId: 1, externalId: 1 }, { unique: true });
notificationRecordSchema.index({ childId: 1, postTime: -1 });
notificationRecordSchema.index({ childId: 1, packageName: 1, postTime: -1 });

export const NotificationRecord = model<INotificationRecord>("NotificationRecord", notificationRecordSchema);
