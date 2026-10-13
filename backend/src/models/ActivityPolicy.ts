import { Schema, model, Types, Document } from "mongoose";
export interface IActivityPolicy extends Document<string> {
  _id: string;
  childId: Types.ObjectId;
  notificationsEnabled: boolean; monitoredPackages: string[];
  callsEnabled: boolean; smsEnabled: boolean; safetyEnabled: boolean; retentionDays: number;
  fullCommunicationHistoryEnabled: boolean; messageBodiesEnabled: boolean; contactsEnabled: boolean; mmsEnabled: boolean; initialImportDays: number;
  deletedBefore?: Record<string, Date>;
}
const schema = new Schema<IActivityPolicy>({
  _id: { type: String, required: true },
  childId: { type: Schema.Types.ObjectId, required: true },
  notificationsEnabled: { type: Boolean, default: false }, monitoredPackages: { type: [String], default: [] },
  callsEnabled: { type: Boolean, default: false }, smsEnabled: { type: Boolean, default: false }, safetyEnabled: { type: Boolean, default: false },
  retentionDays: { type: Number, default: 30 }, deletedBefore: { type: Schema.Types.Mixed, default: {} },
  fullCommunicationHistoryEnabled: {type:Boolean,default:false},messageBodiesEnabled:{type:Boolean,default:false},contactsEnabled:{type:Boolean,default:false},mmsEnabled:{type:Boolean,default:false},initialImportDays:{type:Number,default:7},
}, { timestamps: true });
export const ActivityPolicy = model<IActivityPolicy>("ActivityPolicy", schema);
export const defaultActivityPolicy = { notificationsEnabled: false, monitoredPackages: [] as string[], callsEnabled: false, smsEnabled: false, safetyEnabled: false, retentionDays: 30, fullCommunicationHistoryEnabled:false,messageBodiesEnabled:false,contactsEnabled:false,mmsEnabled:false,initialImportDays:7,deletedBefore: {} as Record<string, Date> };
