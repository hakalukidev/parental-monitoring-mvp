import { Schema, model } from "mongoose";
const schema = new Schema({
  _id:{type:String,required:true}, protocolVersion:Number, androidApi:Number,
  callLogAccess:String,smsAccess:String,contactsAccess:String,defaultSmsRole:Boolean,defaultDialerRole:Boolean,
  callCoverage:String,smsCoverage:String,mmsCoverage:String,
  queuedRecords:Number,droppedRecords:Number,
  lastCallScanAt:Date,lastMessageScanAt:Date,lastCallSyncAt:Date,lastMessageSyncAt:Date,
  updatedAt:{type:Date,default:Date.now},
});
export const CommunicationCapability = model("CommunicationCapability",schema);
