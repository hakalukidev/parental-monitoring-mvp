import { getChildSocketIds } from "../socket/presence";
import { Response } from "express";
import { Device } from "../models/Device";
import { asyncHandler } from "../utils/http";
import { registerDeviceSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";

// POST /api/devices/register (child only) - called on first login / app start
export const registerDevice = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const data = registerDeviceSchema.parse(req.body);
  const childId = req.user!.id;

  // Preserve the primary device and pause state when model/heartbeat display names change.
  const device = await Device.findOneAndUpdate(
    { childId },
    {
      childId,
      deviceName: data.deviceName,
      platform: data.platform,
        ...(data.timeZone ? { timeZone: data.timeZone } : {}),
      ...(data.mediaConsentVersion ? { mediaConsentVersion: data.mediaConsentVersion } : {}),
      status: getChildSocketIds(childId).length ? "ONLINE" : "OFFLINE",
      lastSeen: new Date(),
    },
    { upsert: true, new: true, setDefaultsOnInsert: true, sort: { updatedAt: -1 } }
  );

  res.status(201).json({
    id: device.id,
    deviceName: device.deviceName,
    platform: device.platform,
    status: device.status,
  });
});
