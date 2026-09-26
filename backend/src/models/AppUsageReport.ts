import { Schema, model, Types, Document } from "mongoose";
import { AppCategory, AppPolicyStatus } from "./AppPolicy";

export interface IAppUsageItem {
  packageName: string;
  appName: string;
  category: AppCategory;
  foregroundTimeSeconds: number;
  lastTimeUsed?: Date | null;
  launchCount: number;
  status: AppPolicyStatus;
  dailyLimitMinutes?: number | null;
  isSystemApp: boolean;
}

export interface ICategoryUsageBreakdown {
  category: AppCategory;
  totalTimeSeconds: number;
  percentage: number;
}

export interface IHourlyUsage {
  hour: number; // 0 to 23
  screenTimeSeconds: number;
}

export interface IDowntimeDetails {
  scheduledDowntimeMinutes: number;
  screenOffTimeSeconds: number;
  isDevicePaused: boolean;
  activeScheduleDowntime?: string | null;
  blockedAttemptsCount: number;
  limitsReachedCount: number;
}

export interface IAppUsageReport extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId?: Types.ObjectId | null;
  date: string; // YYYY-MM-DD
  totalScreenTimeSeconds: number;
  totalDowntimeSeconds: number;
  screenOffTimeSeconds: number;
  isDevicePaused: boolean;
  activeScheduleDowntime?: string | null;
  blockedAttemptsCount: number;
  limitsReachedCount: number;
  apps: IAppUsageItem[];
  categoryBreakdown: ICategoryUsageBreakdown[];
  hourlyUsage: IHourlyUsage[];
  lastSyncedAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

const appUsageItemSchema = new Schema<IAppUsageItem>(
  {
    packageName: { type: String, required: true },
    appName: { type: String, required: true },
    category: {
      type: String,
      enum: ["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"],
      default: "OTHER",
    },
    foregroundTimeSeconds: { type: Number, default: 0, min: 0 },
    lastTimeUsed: { type: Date, default: null },
    launchCount: { type: Number, default: 0, min: 0 },
    status: {
      type: String,
      enum: ["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"],
      default: "ALWAYS_ALLOWED",
    },
    dailyLimitMinutes: { type: Number, default: null },
    isSystemApp: { type: Boolean, default: false },
  },
  { _id: false }
);

const categoryUsageSchema = new Schema<ICategoryUsageBreakdown>(
  {
    category: {
      type: String,
      enum: ["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"],
      required: true,
    },
    totalTimeSeconds: { type: Number, default: 0, min: 0 },
    percentage: { type: Number, default: 0, min: 0, max: 100 },
  },
  { _id: false }
);

const hourlyUsageSchema = new Schema<IHourlyUsage>(
  {
    hour: { type: Number, required: true, min: 0, max: 23 },
    screenTimeSeconds: { type: Number, default: 0, min: 0 },
  },
  { _id: false }
);

const appUsageReportSchema = new Schema<IAppUsageReport>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", default: null },
    date: { type: String, required: true, index: true }, // "YYYY-MM-DD"
    totalScreenTimeSeconds: { type: Number, default: 0, min: 0 },
    totalDowntimeSeconds: { type: Number, default: 0, min: 0 },
    screenOffTimeSeconds: { type: Number, default: 0, min: 0 },
    isDevicePaused: { type: Boolean, default: false },
    activeScheduleDowntime: { type: String, default: null },
    blockedAttemptsCount: { type: Number, default: 0, min: 0 },
    limitsReachedCount: { type: Number, default: 0, min: 0 },
    apps: [appUsageItemSchema],
    categoryBreakdown: [categoryUsageSchema],
    hourlyUsage: [hourlyUsageSchema],
    lastSyncedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

// Compound index for querying specific child and date
appUsageReportSchema.index({ childId: 1, date: 1 }, { unique: true });

export const AppUsageReport = model<IAppUsageReport>("AppUsageReport", appUsageReportSchema);
