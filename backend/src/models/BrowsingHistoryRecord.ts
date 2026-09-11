import { Schema, model, Types, Document } from "mongoose";

export type BrowserType =
  | "CHROME"
  | "FIREFOX"
  | "SAMSUNG_BROWSER"
  | "EDGE"
  | "OPERA"
  | "BRAVE"
  | "OTHER";

export type BrowsingCategory =
  | "EDUCATION"
  | "ENTERTAINMENT"
  | "GAMING"
  | "SOCIAL"
  | "ADULT"
  | "SUSPICIOUS"
  | "GENERAL";

export interface IBrowsingHistoryRecord extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  deviceId?: Types.ObjectId | null;
  url: string;
  domain: string;
  title: string;
  browser: BrowserType;
  isIncognito: boolean;
  category?: BrowsingCategory;
  isBlockedAttempt: boolean;
  blockedReason?: string;
  visitedAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

const browsingHistoryRecordSchema = new Schema<IBrowsingHistoryRecord>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    deviceId: { type: Schema.Types.ObjectId, ref: "Device", default: null },
    url: { type: String, required: true },
    domain: { type: String, required: true, index: true },
    title: { type: String, default: "" },
    browser: {
      type: String,
      enum: ["CHROME", "FIREFOX", "SAMSUNG_BROWSER", "EDGE", "OPERA", "BRAVE", "OTHER"],
      default: "OTHER",
    },
    isIncognito: { type: Boolean, default: false },
    category: {
      type: String,
      enum: ["EDUCATION", "ENTERTAINMENT", "GAMING", "SOCIAL", "ADULT", "SUSPICIOUS", "GENERAL"],
      default: "GENERAL",
    },
    isBlockedAttempt: { type: Boolean, default: false },
    blockedReason: { type: String },
    visitedAt: { type: Date, default: Date.now, index: true },
  },
  { timestamps: true }
);

browsingHistoryRecordSchema.index({ childId: 1, visitedAt: -1 });

export const BrowsingHistoryRecord = model<IBrowsingHistoryRecord>(
  "BrowsingHistoryRecord",
  browsingHistoryRecordSchema
);
