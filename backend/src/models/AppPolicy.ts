import { Schema, model, Types, Document } from "mongoose";

export type AppCategory =
  | "GAME"
  | "SOCIAL"
  | "ENTERTAINMENT"
  | "EDUCATION"
  | "PRODUCTIVITY"
  | "OTHER";

export type AppPolicyStatus =
  | "ALWAYS_ALLOWED"
  | "BLOCKED"
  | "TIME_LIMITED"
  | "SCHEDULED";

export interface IAppSchedule {
  daysOfWeek: number[]; // 0 = Sun, 1 = Mon, ... 6 = Sat
  startTime: string;    // "HH:mm" e.g. "21:00"
  endTime: string;      // "HH:mm" e.g. "07:00"
}

export interface IAppPolicy extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  packageName: string;
  appName: string;
  category: AppCategory;
  status: AppPolicyStatus;
  dailyLimitMinutes?: number;
  schedules?: IAppSchedule[];
  isSystemWhitelisted: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const appScheduleSchema = new Schema<IAppSchedule>(
  {
    daysOfWeek: [{ type: Number, min: 0, max: 6 }],
    startTime: { type: String, required: true },
    endTime: { type: String, required: true },
  },
  { _id: false }
);

const appPolicySchema = new Schema<IAppPolicy>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    packageName: { type: String, required: true, index: true },
    appName: { type: String, required: true },
    category: {
      type: String,
      enum: ["GAME", "SOCIAL", "ENTERTAINMENT", "EDUCATION", "PRODUCTIVITY", "OTHER"],
      default: "OTHER",
    },
    status: {
      type: String,
      enum: ["ALWAYS_ALLOWED", "BLOCKED", "TIME_LIMITED", "SCHEDULED"],
      default: "ALWAYS_ALLOWED",
    },
    dailyLimitMinutes: { type: Number, min: 0 },
    schedules: [appScheduleSchema],
    isSystemWhitelisted: { type: Boolean, default: false },
  },
  { timestamps: true }
);

appPolicySchema.index({ childId: 1, packageName: 1 }, { unique: true });

export const AppPolicy = model<IAppPolicy>("AppPolicy", appPolicySchema);
