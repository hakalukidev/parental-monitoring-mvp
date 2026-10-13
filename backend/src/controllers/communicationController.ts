import { Response } from "express";
import { Types } from "mongoose";
import { z } from "zod";
import { AuthedRequest } from "../middleware/auth";
import { asyncHandler, AppError } from "../utils/http";
import { ownedChild } from "../services/authorization";
import { featureEnabled } from "../services/features";
import { CommunicationRecord } from "../models/CommunicationRecord";
import { CommunicationCapability } from "../models/CommunicationCapability";
import { ActivityPolicy, defaultActivityPolicy } from "../models/ActivityPolicy";
import { ActivityEvent } from "../models/ActivityEvent";
import { Device } from "../models/Device";
import { getChildSocketIds } from "../socket/presence";
import { communicationKeyAvailable, communicationDigest, sealCommunication, openCommunication, communicationSearchTerms, securityMessage } from "../services/communicationPrivacy";
import { communicationBatch, communicationKind, communicationCapabilities } from "../services/communicationValidation";

const available=()=>featureEnabled("COMMUNICATIONS")&&communicationKeyAvailable();
async function owner(req:AuthedRequest){const child=await ownedChild({userId:req.user!.id,role:req.user!.role},req.params.childId);req.params.childId=child._id.toString();}
const policy=async(id:string)=>await ActivityPolicy.findById(id).lean()??defaultActivityPolicy;
export const getCommunicationPolicy=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  await owner(req);res.setHeader("Cache-Control","no-store");
  res.json({policy:await policy(req.params.childId),available:available(),online:getChildSocketIds(req.params.childId).length>0,capabilities:await CommunicationCapability.findById(req.params.childId).lean()});
});
export const reportCommunicationCapabilities=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  const data=communicationCapabilities.parse(req.body);
  await CommunicationCapability.findByIdAndUpdate(req.user!.id,{$set:{...data,updatedAt:new Date()}},{upsert:true});res.json({ok:true});
});
export const ingestCommunications=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  const {records,clientChildId}=communicationBatch.parse(req.body),childId=req.user!.id;
  if(clientChildId.toLowerCase()!==childId)throw new AppError("Communication account changed",403);
  if(!available())throw new AppError("Detailed history is unavailable",503);
  const settings=await policy(childId),caps=await CommunicationCapability.findById(childId).lean();
  if(!settings.fullCommunicationHistoryEnabled||caps?.protocolVersion!==2)throw new AppError("Guardian authorization or supported device setup is missing",409);
  for(const record of records){
    if(record.kind==="CALL"?(!settings.callsEnabled||caps.callLogAccess!=="GRANTED"):(!settings.smsEnabled||caps.smsAccess!=="GRANTED"||(record.transport==="MMS"&&!settings.mmsEnabled)))throw new AppError("Provider access or collection is unavailable",409);
  }
  const accepted:string[]=[];let duplicates=0;
  for(const record of records){
    const eventAt=new Date(record.eventAt),observedAt=new Date(record.observedAt),expiresAt=new Date(eventAt.getTime()+settings.retentionDays*86400000);
    const deletedBefore=settings.deletedBefore?.[record.kind];
    if(expiresAt.getTime()<=Date.now()||(deletedBefore&&eventAt<=new Date(deletedBefore))){accepted.push(record.recordId);continue;}
    const sourceKey=record.transport+":"+record.sourceId+":"+eventAt.toISOString();
    const id=childId+":"+record.kind+":"+communicationDigest("record",childId+":"+sourceKey);
    const {recordId:receiptId,kind,transport,direction,...rawDetails}=record;
    const details:Record<string,unknown>={...rawDetails};
    if(!settings.contactsEnabled||((record.kind==="SMS"||record.contactSource==="CONTACTS_PROVIDER")&&caps.contactsAccess!=="GRANTED")){delete details.contactName;delete details.contactSource;}
    const address=record.kind==="CALL"?record.phoneNumber??"":record.address??"";
    let contentStatus="NOT_APPLICABLE";
    if(record.kind==="SMS"){
      contentStatus=record.contentStatus??"EMPTY";
      if(!settings.messageBodiesEnabled){delete details.body;contentStatus="NOT_AUTHORIZED";}
      else if(record.body&&securityMessage(record.body,address)){delete details.body;contentStatus="WITHHELD_SECURITY";}
      else if(record.body){contentStatus="AVAILABLE";}
      else if(!["WITHHELD_SECURITY","TOO_LARGE","NOT_AUTHORIZED","NOT_REPORTED"].includes(contentStatus)){contentStatus="EMPTY";}
      details.contentStatus=contentStatus;
    }
    const row={childId:new Types.ObjectId(childId),kind,transport,eventAt,observedAt,syncedAt:new Date(),direction,
      ...(record.kind==="CALL"?{durationSeconds:record.durationSeconds}:{}),contentStatus,
      addressHash:communicationDigest("address",childId+":"+(address?/^\+?[\d ()-]+$/.test(address)?address.replace(/\D/g,""):address.toLowerCase():sourceKey)),
      threadHash:communicationDigest("thread",childId+":"+(record.kind==="SMS"?(record.threadId??sourceKey):sourceKey)),
      searchTerms:communicationSearchTerms([address,details.contactName,details.body].filter(x=>typeof x==="string").join(" ")),
      sealed:sealCommunication(id,details),expiresAt};
    try{
      const result=await CommunicationRecord.updateOne({_id:id,deletedAt:{$exists:false},$or:[{observedAt:{$lte:observedAt}},{observedAt:{$exists:false}}]},{$set:row,...(record.kind==="CALL"&&record.durationSeconds===undefined?{$unset:{durationSeconds:""}}:{})},{upsert:true});
      if(!result.upsertedCount)duplicates++;
    }catch(error){if(typeof error!=="object"||error===null||!("code" in error)||error.code!==11000)throw error;duplicates++;}
    accepted.push(receiptId);
  }
  const synced:Record<string,Date>={};for(const kind of new Set(records.map(r=>r.kind)))synced[kind==="CALL"?"lastCallSyncAt":"lastMessageSyncAt"]=new Date();
  await CommunicationCapability.findByIdAndUpdate(childId,{$set:synced});res.json({accepted,duplicates});
});

const querySchema=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(500).optional(),search:z.string().trim().max(160).optional(),direction:z.enum(["INCOMING","OUTGOING","MISSED","REJECTED","BLOCKED"]).optional(),transport:z.enum(["CALL","SMS","MMS"]).optional(),threadId:z.string().max(100).regex(/^[\d._:-]+$/).optional(),start:z.string().datetime({offset:true}).optional(),end:z.string().datetime({offset:true}).optional()}).strict();
function filter(req:AuthedRequest){
  const kind=communicationKind.parse(req.params.kind),query=querySchema.parse(req.query);
  if(query.start&&query.end&&new Date(query.start)>new Date(query.end))throw new AppError("Start must precede end",422);
  const scope={childId:new Types.ObjectId(req.params.childId),kind,deletedAt:{$exists:false},expiresAt:{$gt:new Date()},
    ...(query.direction?{direction:query.direction}:{}),...(query.transport?{transport:query.transport}:{}),
    ...(query.threadId?{threadHash:communicationDigest("thread",req.params.childId+":"+query.threadId)}:{}),
    ...(query.search&&communicationSearchTerms(query.search).length?{searchTerms:{$all:communicationSearchTerms(query.search)}}:{}),
    ...(query.start||query.end?{eventAt:{...(query.start?{$gte:new Date(query.start)}:{}),...(query.end?{$lte:new Date(query.end)}:{})}}:{})};
  return {kind,query,scope};
}
function cursor(raw:string|undefined,child:string,kind:string){
  if(!raw)return undefined;
  try{const data=z.object({child:z.literal(child),kind:z.literal(kind),id:z.string().max(200),at:z.string().datetime()}).strict().parse(JSON.parse(Buffer.from(raw,"base64url").toString()));return data;}
  catch{throw new AppError("Invalid communication cursor",422);}
}
function nextCursor(child:string,kind:string,id:string,at:Date){return Buffer.from(JSON.stringify({child,kind,id,at:at.toISOString()})).toString("base64url");}
function publicRecord(row:{_id:string;sealed?:string|null;eventAt:Date;observedAt:Date;syncedAt?:Date;kind:string;transport:string;direction?:string|null;durationSeconds?:number|null;contentStatus?:string|null}){
  if(!row.sealed)throw new AppError("History content is unavailable",503);
  let details:Record<string,unknown>;try{details=openCommunication(row._id,row.sealed);}catch{throw new AppError("History encryption key is unavailable",503);}
  return {id:row._id,kind:row.kind,transport:row.transport,eventAt:row.eventAt,observedAt:row.observedAt,syncedAt:row.syncedAt,direction:row.direction,durationSeconds:row.durationSeconds,contentStatus:row.contentStatus,details};
}
export const listCommunications=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  await owner(req);if(!communicationKeyAvailable())throw new AppError("History encryption is unavailable",503);
  const {kind,query,scope}=filter(req),pageCursor=cursor(query.cursor,req.params.childId,kind);
  const rows=await CommunicationRecord.find({...scope,...(pageCursor?{$or:[{eventAt:{$lt:new Date(pageCursor.at)}},{eventAt:new Date(pageCursor.at),_id:{$gt:pageCursor.id}}]}:{})}).sort({eventAt:-1,_id:1}).limit(query.limit+1).lean();
  const page=rows.slice(0,query.limit),last=page[page.length-1];res.setHeader("Cache-Control","no-store");
  res.json({records:page.map(publicRecord),total:await CommunicationRecord.countDocuments(scope),nextCursor:rows.length>query.limit?nextCursor(req.params.childId,kind,last._id,last.eventAt):null});
});
export const communicationGroups=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  await owner(req);if(!communicationKeyAvailable())throw new AppError("History encryption is unavailable",503);
  const {kind,query,scope}=filter(req),pageCursor=cursor(query.cursor,req.params.childId,kind+"-GROUPS");
  const result=await CommunicationRecord.aggregate([{$match:scope},{$sort:{eventAt:-1,_id:1}},{$group:{_id:kind==="CALL"?"$addressHash":"$threadHash",count:{$sum:1},durationSeconds:{$sum:{$ifNull:["$durationSeconds",0]}},latestAt:{$first:"$eventAt"},latest:{$first:"$$ROOT"}}},{$facet:{total:[{$count:"count"}],page:[...(pageCursor?[{$match:{$or:[{latestAt:{$lt:new Date(pageCursor.at)}},{latestAt:new Date(pageCursor.at),_id:{$gt:pageCursor.id}}]}}]:[]),{$sort:{latestAt:-1,_id:1}},{$limit:query.limit+1}]}}]);
  const groups=result[0].page,page=groups.slice(0,query.limit),last=page[page.length-1];res.setHeader("Cache-Control","no-store");
  res.json({groups:page.map((g:{_id:string;count:number;durationSeconds:number;latestAt:Date;latest:Parameters<typeof publicRecord>[0]})=>({id:g._id,count:g.count,durationSeconds:g.durationSeconds,latestAt:g.latestAt,latest:publicRecord(g.latest)})),total:result[0].total[0]?.count??0,nextCursor:groups.length>query.limit?nextCursor(req.params.childId,kind+"-GROUPS",last._id,last.latestAt):null});
});
export const communicationStats=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  await owner(req);const {kind,scope}=filter(req);const device=await Device.findOne({childId:req.params.childId}).sort({updatedAt:-1}).select("timeZone").lean();
  let timeZone=device?.timeZone??"UTC";try{new Intl.DateTimeFormat("en",{timeZone}).format(new Date());}catch{timeZone="UTC";}
  const [daily,weekly]=await Promise.all(["%Y-%m-%d","%G-W%V"].map(format=>CommunicationRecord.aggregate([{$match:scope},{$group:{_id:{day:{$dateToString:{date:"$eventAt",format,timezone:timeZone}},direction:"$direction"},count:{$sum:1},durationSeconds:{$sum:{$ifNull:["$durationSeconds",0]}}}},{$sort:{"_id.day":-1,"_id.direction":1}}])));
  res.setHeader("Cache-Control","no-store");res.json({kind,timeZone,daily,weekly,coverage:"Authorized provider records within configured import/retention; not complete phone communications"});
});
export const deleteCommunications=asyncHandler(async(req:AuthedRequest,res:Response)=>{
  await owner(req);const kind=communicationKind.parse(req.params.kind);z.object({confirmation:z.literal("DELETE_COMMUNICATIONS")}).strict().parse(req.body);
  const cutoff=new Date();await ActivityPolicy.findByIdAndUpdate(req.params.childId,{$set:{[`deletedBefore.${kind}`]:cutoff},$setOnInsert:{childId:req.params.childId}},{upsert:true,setDefaultsOnInsert:true});
  // Keep only short-lived opaque deduplication tombstones, preventing future-dated replay after deletion.
  const result=await CommunicationRecord.updateMany({childId:req.params.childId,kind,deletedAt:{$exists:false}},{$set:{deletedAt:cutoff},$unset:{sealed:"",searchTerms:"",addressHash:"",threadHash:"",direction:"",durationSeconds:"",contentStatus:"",eventAt:"",observedAt:"",syncedAt:"",transport:""}});
  await ActivityEvent.deleteMany({childId:req.params.childId,kind});res.json({deleted:result.modifiedCount,deletedBefore:cutoff});
});
