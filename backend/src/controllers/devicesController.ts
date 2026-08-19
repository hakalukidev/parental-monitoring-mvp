import { Response } from "express";
import { Device } from "../models/Device";
import { asyncHandler } from "../utils/http";
import { registerDeviceSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";

// POST /api/devices/register (child only) - called on first login / app start
export const registerDevice = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const data = registerDeviceSchema.parse(req.body);
  const childId = req.user!.id;

  // A child has (for this MVP) a single primary device record; upsert by childId+deviceName
  const device = await Device.findOneAndUpdate(
    { childId, deviceName: data.deviceName },
    {
      childId,
      deviceName: data.deviceName,
      platform: data.platform,
      status: "OFFLINE", // becomes ONLINE once the socket connects
      lastSeen: new Date(),
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

  res.status(201).json({
    id: device.id,
    deviceName: device.deviceName,
    platform: device.platform,
    status: device.status,
  });
});
