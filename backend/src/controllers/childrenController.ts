import { Response } from "express";
import { User } from "../models/User";
import { Device } from "../models/Device";
import { hashPassword } from "../utils/password";
import { asyncHandler, AppError } from "../utils/http";
import { createChildSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";

function trialExpiry() {
  const expiry = new Date();
  expiry.setDate(expiry.getDate() + 3);
  return expiry;
}

// POST /api/children  (parent only)
export const createChild = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const data = createChildSchema.parse(req.body);
  const parentId = req.user!.id;

  const loginId = data.username.toLowerCase().trim();
  const existing = await User.findOne({ email: loginId });
  if (existing) throw new AppError("Username already taken", 409);

  const passwordHash = await hashPassword(data.password);
  const child = await User.create({
    name: data.name,
    email: loginId,
    passwordHash,
    role: "CHILD",
    parentId,
    expireDate: trialExpiry(),
  });

  res.status(201).json({
    id: child.id,
    name: child.name,
    username: child.email,
    role: child.role,
  });
});

// GET /api/children  (parent only) - list this parent's children with device + status
export const listChildren = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const children = await User.find({ role: "CHILD", parentId }).lean();

  const results = await Promise.all(
    children.map(async (child) => {
      const device = await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean();
      return {
        id: child._id,
        name: child.name,
        username: child.email,
        device: device
          ? {
              id: device._id,
              deviceName: device.deviceName,
              platform: device.platform,
              status: device.status,
              lastSeen: device.lastSeen,
            }
          : null,
      };
    })
  );

  res.json({ children: results });
});

// GET /api/children/:id (parent only, must own the child)
export const getChild = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const child = await User.findOne({ _id: req.params.id, role: "CHILD", parentId }).lean();
  if (!child) throw new AppError("Child not found", 404);

  const device = await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean();

  res.json({
    id: child._id,
    name: child.name,
    username: child.email,
    device: device
      ? {
          id: device._id,
          deviceName: device.deviceName,
          platform: device.platform,
          status: device.status,
          lastSeen: device.lastSeen,
        }
      : null,
  });
});

/** Helper used elsewhere (screen-share controller, sockets) to verify parent->child ownership. */
export async function assertParentOwnsChild(parentId: string, childId: string) {
  const child = await User.findOne({ _id: childId, role: "CHILD", parentId });
  if (!child) throw new AppError("Child not found or not owned by this parent", 403);
  return child;
}
