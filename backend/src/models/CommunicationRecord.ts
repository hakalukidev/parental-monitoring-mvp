import { Schema, model } from "mongoose";
const schema = new Schema({
  _id: { type: String, required: true }, childId: { type: Schema.Types.ObjectId, required: true },
  kind: { type: String, enum: ["CALL","SMS"], required: true }, transport: { type: String, enum: ["CALL","SMS","MMS"], required: true },
  eventAt: { type: Date, required: true }, observedAt: { type: Date, required: true }, syncedAt: { type: Date, default: Date.now },
  direction: String, durationSeconds: Number, addressHash: String, threadHash: String,
  sealed: String, searchTerms: [String], contentStatus: String,
  expiresAt: { type: Date, required: true }, deletedAt: Date,
}, {strict:"throw"});
schema.index({childId:1,kind:1,eventAt:-1,_id:1});
schema.index({childId:1,kind:1,searchTerms:1,eventAt:-1});
schema.index({childId:1,kind:1,addressHash:1,eventAt:-1});
schema.index({expiresAt:1},{expireAfterSeconds:0});
export const CommunicationRecord = model("CommunicationRecord",schema);
