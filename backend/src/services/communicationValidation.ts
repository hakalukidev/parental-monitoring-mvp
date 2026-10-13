import { z } from "zod";
import { objectIdSchema } from "./authorization";
export const communicationKind=z.enum(["CALL","SMS"]);
const sourceId=z.string().min(1).max(100).regex(/^[\d._:-]+$/);
const at=z.string().datetime({offset:true}).refine(x=>new Date(x).getTime()<=Date.now()+300000,"Timestamp is in the future");
const label=z.string().max(255);
const common={recordId:z.string().min(1).max(128).regex(/^[a-f\d]+$/),sourceId,eventAt:at,observedAt:at,contactName:label.optional(),contactSource:z.enum(["CACHED_CALL_LOG","CONTACTS_PROVIDER"]).optional(),subscriptionId:label.optional()};
export const communicationBatch=z.object({clientChildId:objectIdSchema,records:z.array(z.discriminatedUnion("kind",[
  z.object({...common,kind:z.literal("CALL"),transport:z.literal("CALL"),direction:z.enum(["INCOMING","OUTGOING","MISSED","REJECTED","BLOCKED"]),durationSeconds:z.number().int().min(0).max(86400).optional(),phoneNumber:label.optional(),phoneAccountId:label.optional(),phoneAccountComponent:label.optional()}).strict(),
  z.object({...common,kind:z.literal("SMS"),transport:z.enum(["SMS","MMS"]),direction:z.enum(["INCOMING","OUTGOING"]),address:label.optional(),body:z.string().max(32000).optional(),threadId:sourceId.optional(),dateSent:at.optional(),read:z.boolean().optional(),deliveryStatus:z.enum(["NONE","COMPLETE","PENDING","FAILED","UNKNOWN"]).optional(),contentStatus:z.enum(["AVAILABLE","EMPTY","NOT_AUTHORIZED","NOT_REPORTED","WITHHELD_SECURITY","TOO_LARGE"]).optional(),mmsType:z.number().int().min(0).max(255).optional(),attachmentCount:z.number().int().min(0).max(100).optional()}).strict(),
])).min(1).max(50)}).strict();
const access=z.enum(["GRANTED","DENIED_OR_RESTRICTED","RESTRICTED","UNAVAILABLE","UNKNOWN"]);
export const communicationCapabilities=z.object({protocolVersion:z.literal(2),androidApi:z.number().int().min(26).max(100),callLogAccess:access,smsAccess:access,contactsAccess:access,defaultSmsRole:z.boolean(),defaultDialerRole:z.boolean(),callCoverage:z.enum(["PUBLIC_CALL_LOG","UNAVAILABLE"]),smsCoverage:z.enum(["PUBLIC_SMS_PROVIDER","UNAVAILABLE"]),mmsCoverage:z.enum(["PROVIDER_TEXT_METADATA","UNAVAILABLE"]),queuedRecords:z.number().int().min(0).max(4000),droppedRecords:z.number().int().min(0).max(2147483647),lastCallScanAt:at.optional(),lastMessageScanAt:at.optional()}).strict();
