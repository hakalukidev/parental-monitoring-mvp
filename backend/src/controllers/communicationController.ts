import { Response } from "express";
import { Types } from "mongoose";
import { AuthedRequest } from "../middleware/auth";
import { Device } from "../models/Device";
import { CallRecord, CallDirection } from "../models/CallRecord";
import { SmsRecord, SmsDirection } from "../models/SmsRecord";
import { CommunicationCapability } from "../models/CommunicationCapability";
import { assertParentOwnsChild } from "./childrenController";
import { asyncHandler, AppError } from "../utils/http";
import {
  syncCallsBatchSchema,
  syncSmsBatchSchema,
  updateCommunicationCapabilitySchema,
  communicationHistoryQuerySchema,
} from "../utils/validation";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";
import { User } from "../models/User";

// POST /api/children/:childId/communication/calls/batch (child only)
export const syncCallsBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  // Authorization check
  if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden: cannot sync calls for another child", 403);
  }

  const { calls } = syncCallsBatchSchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) {
    throw new AppError("Device not registered for child", 404);
  }
  const deviceId = device._id;

  const childObjectId = new Types.ObjectId(childId);

  // Deduplication via bulkWrite upsert with $setOnInsert
  const bulkOps = calls.map((call) => ({
    updateOne: {
      filter: { childId: childObjectId, externalId: call.externalId },
      update: {
        $setOnInsert: {
          childId: childObjectId,
          deviceId: deviceId,
          externalId: call.externalId,
          phoneNumber: call.phoneNumber || null,
          contactName: call.contactName || null,
          direction: call.direction as CallDirection,
          durationSeconds: call.durationSeconds || 0,
          timestamp: new Date(call.timestamp),
        },
      },
      upsert: true,
    },
  }));

  const bulkRes = await CallRecord.bulkWrite(bulkOps as any);

  // Notify parent sockets in real-time if new calls were inserted
  if (bulkRes.upsertedCount > 0) {
    const child = await User.findById(childId);
    if (child && child.parentId) {
      const parentSocketIds = getParentSocketIds(child.parentId.toString());
      for (const sId of parentSocketIds) {
        getIO().to(sId).emit("new_call_activity", {
          childId,
          newCount: bulkRes.upsertedCount,
        });
      }
    }
  }

  res.status(200).json({
    success: true,
    processedCount: calls.length,
    upsertedCount: bulkRes.upsertedCount,
  });
});

// POST /api/children/:childId/communication/sms/batch (child only)
export const syncSmsBatch = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden: cannot sync SMS for another child", 403);
  }

  const { messages } = syncSmsBatchSchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });
  if (!device) {
    throw new AppError("Device not registered for child", 404);
  }
  const deviceId = device._id;

  const childObjectId = new Types.ObjectId(childId);

  // Deduplication via bulkWrite upsert with $setOnInsert
  const bulkOps = messages.map((sms) => ({
    updateOne: {
      filter: { childId: childObjectId, externalId: sms.externalId },
      update: {
        $setOnInsert: {
          childId: childObjectId,
          deviceId: deviceId,
          externalId: sms.externalId,
          phoneNumber: sms.phoneNumber || null,
          contactName: sms.contactName || null,
          direction: sms.direction as SmsDirection,
          body: sms.body || null,
          hasBody: sms.hasBody || !!sms.body,
          timestamp: new Date(sms.timestamp),
        },
      },
      upsert: true,
    },
  }));

  const bulkRes = await SmsRecord.bulkWrite(bulkOps as any);

  // Notify parent sockets in real-time
  if (bulkRes.upsertedCount > 0) {
    const child = await User.findById(childId);
    if (child && child.parentId) {
      const parentSocketIds = getParentSocketIds(child.parentId.toString());
      for (const sId of parentSocketIds) {
        getIO().to(sId).emit("new_sms_activity", {
          childId,
          newCount: bulkRes.upsertedCount,
        });
      }
    }
  }

  res.status(200).json({
    success: true,
    processedCount: messages.length,
    upsertedCount: bulkRes.upsertedCount,
  });
});

// POST /api/children/:childId/communication/capabilities (child or parent)
export const reportCapabilities = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden: cannot report capabilities for another child", 403);
  }
  if (role === "PARENT") {
    await assertParentOwnsChild(userId, childId);
  }

  const parsed = updateCommunicationCapabilitySchema.parse(req.body);

  const device = await Device.findOne({ childId }).sort({ updatedAt: -1 });

  const capability = await CommunicationCapability.findOneAndUpdate(
    { childId },
    {
      childId,
      deviceId: device?._id || null,
      callsStatus: parsed.callsStatus,
      smsMetadataStatus: parsed.smsMetadataStatus,
      smsContentStatus: parsed.smsContentStatus,
      updatedAt: new Date(),
    },
    { upsert: true, new: true }
  );

  // Notify parent in real-time
  const child = await User.findById(childId);
  if (child && child.parentId) {
    const parentSocketIds = getParentSocketIds(child.parentId.toString());
    for (const sId of parentSocketIds) {
      getIO().to(sId).emit("communication_capabilities_updated", {
        childId,
        capabilities: capability,
      });
    }
  }

  res.status(200).json(capability);
});

// GET /api/children/:childId/communication/capabilities (parent or child)
export const getCapabilities = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const userId = req.user!.id;
  const role = req.user!.role;

  if (role === "PARENT") {
    await assertParentOwnsChild(userId, childId);
  } else if (role === "CHILD" && userId !== childId) {
    throw new AppError("Forbidden", 403);
  }

  const capability = await CommunicationCapability.findOne({ childId });
  if (!capability) {
    return res.status(200).json({
      childId,
      callsStatus: "PERMISSION_REQUIRED",
      smsMetadataStatus: "PERMISSION_REQUIRED",
      smsContentStatus: "PERMISSION_REQUIRED",
      updatedAt: new Date(),
    });
  }

  res.status(200).json(capability);
});

// GET /api/children/:childId/communication/calls (parent only)
export const getCalls = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const query = communicationHistoryQuerySchema.parse(req.query);

  const filter: any = { childId };

  if (query.direction && query.direction !== "ALL") {
    filter.direction = query.direction.toUpperCase();
  }

  if (query.search) {
    const searchRegex = new RegExp(query.search.trim(), "i");
    filter.$or = [{ contactName: searchRegex }, { phoneNumber: searchRegex }];
  }

  if (query.startDate || query.endDate) {
    filter.timestamp = {};
    if (query.startDate) filter.timestamp.$gte = new Date(query.startDate);
    if (query.endDate) filter.timestamp.$lte = new Date(query.endDate);
  }

  const page = query.page;
  const limit = query.limit;
  const skip = (page - 1) * limit;

  const [calls, total] = await Promise.all([
    CallRecord.find(filter).sort({ timestamp: -1 }).skip(skip).limit(limit),
    CallRecord.countDocuments(filter),
  ]);

  res.status(200).json({
    calls,
    total,
    page,
    totalPages: Math.ceil(total / limit) || 1,
  });
});

// GET /api/children/:childId/communication/sms (parent only)
export const getSms = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const { childId } = req.params;
  const parentId = req.user!.id;

  await assertParentOwnsChild(parentId, childId);

  const query = communicationHistoryQuerySchema.parse(req.query);

  const filter: any = { childId };

  if (query.direction && query.direction !== "ALL") {
    filter.direction = query.direction.toUpperCase();
  }

  if (query.search) {
    const searchRegex = new RegExp(query.search.trim(), "i");
    filter.$or = [{ contactName: searchRegex }, { phoneNumber: searchRegex }];
  }

  if (query.startDate || query.endDate) {
    filter.timestamp = {};
    if (query.startDate) filter.timestamp.$gte = new Date(query.startDate);
    if (query.endDate) filter.timestamp.$lte = new Date(query.endDate);
  }

  const page = query.page;
  const limit = query.limit;
  const skip = (page - 1) * limit;

  const [messages, total] = await Promise.all([
    SmsRecord.find(filter).sort({ timestamp: -1 }).skip(skip).limit(limit),
    SmsRecord.countDocuments(filter),
  ]);

  res.status(200).json({
    messages,
    total,
    page,
    totalPages: Math.ceil(total / limit) || 1,
  });
});
