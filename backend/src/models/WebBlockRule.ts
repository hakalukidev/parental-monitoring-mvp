import { Schema, model, Types, Document } from "mongoose";

export type WebRuleType = "DOMAIN" | "KEYWORD" | "CATEGORY";
export type WebRuleAction = "BLOCK" | "ALLOW";

export interface IWebBlockRule extends Document {
  _id: Types.ObjectId;
  childId: Types.ObjectId;
  ruleType: WebRuleType;
  target: string;
  action: WebRuleAction;
  isEnabled: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const webBlockRuleSchema = new Schema<IWebBlockRule>(
  {
    childId: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
    ruleType: {
      type: String,
      enum: ["DOMAIN", "KEYWORD", "CATEGORY"],
      required: true,
    },
    target: { type: String, required: true },
    action: {
      type: String,
      enum: ["BLOCK", "ALLOW"],
      default: "BLOCK",
    },
    isEnabled: { type: Boolean, default: true },
  },
  { timestamps: true }
);

webBlockRuleSchema.index({ childId: 1, ruleType: 1, target: 1 });

export const WebBlockRule = model<IWebBlockRule>("WebBlockRule", webBlockRuleSchema);
