import { Schema, model } from "mongoose";
const schema = new Schema({
  _id: { type: String, required: true },
  sessionId: { type: Schema.Types.ObjectId, required: true },
  expiresAt: { type: Date, required: true },
});
export const MediaLease = model("MediaLease", schema);
