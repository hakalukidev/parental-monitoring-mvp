import { Schema, model } from "mongoose";

// New, bounded request metadata. No message/body content is retained.
const schema = new Schema({
  _id: { type: String, required: true },
  childId: { type: Schema.Types.ObjectId, required: true },
  parentId: { type: Schema.Types.ObjectId, required: true },
  requestId: { type: String, required: true, maxlength: 100 },
  packageName: { type: String, required: true, maxlength: 255 },
  expiresAt: { type: Date, required: true },
  resolvedAt: { type: Date, default: null },
});
schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
export const UnblockRequest = model("UnblockRequest", schema);
