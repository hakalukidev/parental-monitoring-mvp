import { Response } from "express";
import { z } from "zod";
import { ActivityPolicy, defaultActivityPolicy } from "../models/ActivityPolicy";
import { ActivityEvent } from "../models/ActivityEvent";
import { ActivityCapability } from "../models/ActivityCapability";
import { AuthedRequest } from "../middleware/auth";
import { asyncHandler, AppError } from "../utils/http";
import { ownedChild } from "../services/authorization";
import { featureEnabled } from "../services/features";
import { activityBatch, activityKind, activityPolicyUpdate, activityCapabilities, sensitivePackage, approvedSafetyModels } from "../services/activityValidation";
import { getChildSocketIds } from "../socket/presence";
import { getIO } from "../socket/io";
import { ScreenShareSession } from "../models/ScreenShareSession";
import { CameraStreamSession } from "../models/CameraStreamSession";
import { AudioSession } from "../models/AudioSession";
import { CommunicationRecord } from "../models/CommunicationRecord";
import { communicationKeyAvailable } from "../services/communicationPrivacy";

async function policy(childId: string) { return await ActivityPolicy.findById(childId).lean() ?? defaultActivityPolicy; }
function features() { const communications=featureEnabled("COMMUNICATIONS")&&communicationKeyAvailable();return { notifications: featureEnabled("NOTIFICATIONS"), callSms: featureEnabled("CALL_SMS")||communications,communications,safety: featureEnabled("SAFETY") && approvedSafetyModels().length > 0 }; }
const owner = async (req: AuthedRequest) => {
  const child = await ownedChild({ userId: req.user!.id, role: req.user!.role }, req.params.childId);
  req.params.childId = child._id.toString(); // String policy IDs use the same canonical identity as child authentication.
  return child;
};
export const getMyActivityPolicy = asyncHandler(async (req: AuthedRequest, res: Response) => { res.json({ policy: await policy(req.user!.id), features: features(), approvedModels: approvedSafetyModels() }); });
export const getActivityPolicy = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await owner(req);
  const filter = { childId: req.params.childId, startedAt: { $ne: null }, offerSentAt: { $ne: null }, answerReceivedAt: { $ne: null }, status: "ENDED", endedBy: { $in: ["PARENT","CHILD"] } };
  const lastCheckIns = {
    screen: await ScreenShareSession.findOne(filter).sort({endedAt:-1}).select("startedAt endedAt").lean(),
    camera: await CameraStreamSession.findOne(filter).sort({endedAt:-1}).select("startedAt endedAt").lean(),
    audio: await AudioSession.findOne(filter).sort({endedAt:-1}).select("startedAt endedAt").lean(),
  };
  res.json({ policy: await policy(req.params.childId), features: features(), capabilities: await ActivityCapability.findById(req.params.childId).lean(), online: getChildSocketIds(req.params.childId).length > 0, lastCheckIns });
});
export const updateActivityPolicy = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await owner(req); const data = activityPolicyUpdate.parse(req.body), available = features();
  if ((data.notificationsEnabled && !available.notifications) || ((data.callsEnabled || data.smsEnabled) && !available.callSms) || (data.safetyEnabled && !available.safety)) throw new AppError("This collector is disabled pending platform/model verification", 503);
  if ((data.fullCommunicationHistoryEnabled||data.messageBodiesEnabled||data.contactsEnabled||data.mmsEnabled)&&!available.communications)throw new AppError("Detailed history is unavailable pending encryption/platform verification",503);
  if (data.monitoredPackages?.some(sensitivePackage)) throw new AppError("Security, banking and system apps cannot be monitored", 422);
  const saved = await ActivityPolicy.findByIdAndUpdate(req.params.childId, { $set: data, $setOnInsert: { childId: req.params.childId } }, { upsert: true, new: true, setDefaultsOnInsert: true });
  if (data.retentionDays !== undefined) {
    const update=[{ $set: { expiresAt: { $add: ["$eventAt", data.retentionDays * 86400000] } } }];
    await ActivityEvent.updateMany({ childId: req.params.childId },update);
    await CommunicationRecord.updateMany({ childId: req.params.childId,deletedAt:{$exists:false} },update);
  }
  const ids = getChildSocketIds(req.params.childId);
  if (ids.length) getIO().to(ids).emit("activity_policy_updated", { requestedAt: new Date().toISOString() });
  res.json({ policy: saved });
});
export const reportActivityCapabilities = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const data = activityCapabilities.parse(req.body);
  await ActivityCapability.findByIdAndUpdate(req.user!.id, { $set: { ...data, updatedAt: new Date() } }, { upsert: true, setDefaultsOnInsert: true });
  res.json({ ok: true });
});
export const ingestActivity = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { events, clientChildId } = activityBatch.parse(req.body), childId = req.user!.id, settings = await policy(childId), available = features();
  if (clientChildId && clientChildId.toLowerCase() !== childId) throw new AppError("Activity account changed", 403);
  const capability = await ActivityCapability.findById(childId).lean();
  for (const event of events) {
    const authorized = event.kind === "NOTIFICATION" ? available.notifications && settings.notificationsEnabled && capability?.notificationAccess === "GRANTED" && capability.listenerConnected && settings.monitoredPackages.includes(event.packageName) && !sensitivePackage(event.packageName)
      : event.kind === "CALL" ? available.callSms && settings.callsEnabled && capability?.callLogAccess === "GRANTED"
        : event.kind === "SMS" ? available.callSms && settings.smsEnabled && capability?.smsAccess === "GRANTED"
          : available.safety && settings.safetyEnabled && capability?.safetyModel === "AVAILABLE" && approvedSafetyModels().includes(event.modelVersion);
    if (!authorized) throw new AppError("Activity collection is not enabled or its device access is unavailable", 409);
  }
  const accepted: string[] = []; let duplicates = 0;
  for (const event of events) {
    const eventAt = new Date(event.eventAt), expiresAt = new Date(eventAt.getTime() + settings.retentionDays * 86400000);
    const cutoff = settings.deletedBefore?.[event.kind];
    // A receipt drains an old queue without resurrecting explicitly deleted/expired history.
    if (expiresAt.getTime() <= Date.now() || (cutoff && eventAt <= new Date(cutoff))) { accepted.push(event.eventId); continue; }
    const id = `${childId}:${event.kind}:${event.eventId}`;
    try {
      const result = await ActivityEvent.updateOne({ _id: id }, { $setOnInsert: { ...event, childId, eventAt, expiresAt, syncedAt: new Date() } }, { upsert: true });
      if (!result.upsertedCount) duplicates++;
    } catch (error) { if (typeof error !== "object" || error === null || !("code" in error) || error.code !== 11000) throw error; duplicates++; }
    accepted.push(event.eventId);
  }
  await ActivityCapability.findByIdAndUpdate(childId, { $set: { lastSyncedAt: new Date() } });
  res.json({ accepted, duplicates });
});
export const listActivity = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await owner(req); const kind = activityKind.parse(req.params.kind);
  const query = z.object({ limit: z.coerce.number().int().min(1).max(200).default(50), cursor: z.string().max(400).optional(), packageName: z.string().max(255).optional(), start: z.string().datetime({offset:true}).optional(), end: z.string().datetime({offset:true}).optional() }).parse(req.query);
  if (query.start && query.end && new Date(query.start).getTime() > new Date(query.end).getTime()) throw new AppError("Start must precede end", 422);
  let cursorFilter = {};
  if (query.cursor) {
    try {
      const cursor = z.object({ id: z.string().max(200), at: z.string().datetime() }).parse(JSON.parse(Buffer.from(query.cursor, "base64url").toString()));
      if (!cursor.id.startsWith(`${req.params.childId.toLowerCase()}:${kind}:`)) throw new Error("Wrong cursor scope");
      cursorFilter = { $or: [{ eventAt: { $lt: new Date(cursor.at) } }, { eventAt: new Date(cursor.at), _id: { $gt: cursor.id } }] };
    } catch { throw new AppError("Invalid activity cursor", 422); }
  }
  const filter = { childId: req.params.childId, kind, expiresAt: { $gt: new Date() }, ...cursorFilter, ...(query.packageName ? { packageName: query.packageName } : {}), ...(query.start || query.end ? { eventAt: { ...(query.start ? {$gte:new Date(query.start)} : {}), ...(query.end ? {$lte:new Date(query.end)} : {}) } } : {}) };
  const records = await ActivityEvent.find(filter).sort({ eventAt: -1, _id: 1 }).limit(query.limit + 1).lean(); const page = records.slice(0, query.limit);
  const total = await ActivityEvent.countDocuments({childId:req.params.childId,kind,expiresAt:{$gt:new Date()},...(query.packageName?{packageName:query.packageName}:{}),...(query.start||query.end?{eventAt:{...(query.start?{$gte:new Date(query.start)}:{}),...(query.end?{$lte:new Date(query.end)}:{})}}:{})});
  const last = page[page.length-1];
  res.setHeader("Cache-Control", "no-store");res.json({ records: page, total, nextCursor: records.length > query.limit ? Buffer.from(JSON.stringify({id:last._id,at:last.eventAt.toISOString()})).toString("base64url") : null });
});
export const deleteActivity = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await owner(req); const kind = activityKind.parse(req.params.kind);
  z.object({ confirmation: z.literal("DELETE_ACTIVITY") }).strict().parse(req.body);
  const cutoff = new Date();
  await ActivityPolicy.findByIdAndUpdate(req.params.childId,{$set:{[`deletedBefore.${kind}`]:cutoff},$setOnInsert:{childId:req.params.childId}},{upsert:true,setDefaultsOnInsert:true});
  const result = await ActivityEvent.deleteMany({childId:req.params.childId,kind,syncedAt:{$lte:cutoff}});
  let detailed=0;
  if(kind==="CALL"||kind==="SMS") {
    const erased=await CommunicationRecord.updateMany({childId:req.params.childId,kind,deletedAt:{$exists:false}},{$set:{deletedAt:cutoff},$unset:{sealed:"",searchTerms:"",addressHash:"",threadHash:"",direction:"",durationSeconds:"",contentStatus:"",eventAt:"",observedAt:"",syncedAt:"",transport:""}});
    detailed=erased.modifiedCount;
  }
  res.json({ deleted: result.deletedCount+detailed, deletedBefore: cutoff });
});
export const reviewSafetyEvent = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await owner(req); const { reviewStatus } = z.object({reviewStatus:z.enum(["CONFIRMED","DISMISSED"])}).strict().parse(req.body);
  const record = await ActivityEvent.findOneAndUpdate({_id:req.params.eventId,childId:req.params.childId,kind:"SAFETY"},{$set:{reviewStatus}},{new:true});
  if(!record)throw new AppError("Safety event not found",404);res.json({record});
});
