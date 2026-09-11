import { Schema, model, Types, Document } from "mongoose";

export interface IInstalledApp extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  packageName: string;
  appName: string;
  category: string;
  versionName?: string;
  isSystemApp: boolean;
  syncedAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

const installedAppSchema = new Schema<IInstalledApp>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    packageName: { type: String, required: true, index: true },
    appName: { type: String, required: true },
    category: { type: String, default: "OTHER" },
    versionName: { type: String },
    isSystemApp: { type: Boolean, default: false },
    syncedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

installedAppSchema.index({ childId: 1, packageName: 1 }, { unique: true });

export const InstalledApp = model<IInstalledApp>("InstalledApp", installedAppSchema);
