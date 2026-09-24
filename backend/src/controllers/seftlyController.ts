import { Request, Response } from "express";
import { Device } from "../models/Device";
import { User } from "../models/User";
import { AuthedRequest } from "../middleware/auth";
import { asyncHandler, AppError } from "../utils/http";
import { hashPassword, verifyPassword } from "../utils/password";
import { signAccessToken, signRefreshToken } from "../utils/jwt";
import { env } from "../config/env";

function premium(expireDate?: Date | null) {
  const expiresAt = expireDate ? new Date(expireDate).getTime() : 0;
  const isPremium = expiresAt >= Date.now();
  return {
    expireDate: expireDate ? new Date(expireDate).toISOString().slice(0, 10) : null,
    isPremium,
    daysRemaining: isPremium ? Math.ceil((expiresAt - Date.now()) / 86_400_000) : 0,
  };
}

function profile(user: { _id: unknown; name: string; email: string; role: string; parentId?: unknown }) {
  return {
    id: String(user._id),
    name: user.name,
    email: user.email,
    username: user.email,
    role: user.role,
    parentId: user.parentId,
  };
}

// POST /api/parent/login - Seftly website compatibility route.
export const seftlyParentLogin = asyncHandler(async (req: Request, res: Response) => {
  const email = String(req.body?.email ?? "").trim().toLowerCase();
  const password = String(req.body?.password ?? "");
  const user = await User.findOne({ email, role: "PARENT" });
  if (!user || !(await verifyPassword(user.passwordHash, password))) {
    throw new AppError("Invalid parent email or password", 401);
  }
  const token = signAccessToken({ sub: user.id, role: "PARENT" });
  const refreshToken = signRefreshToken({ sub: user.id, role: "PARENT", tokenVersion: user.refreshTokenVersion });
  res.json({ token, refreshToken, profile: profile(user) });
});

// POST /api/child/login - Seftly website compatibility route.
export const seftlyChildLogin = asyncHandler(async (req: Request, res: Response) => {
  const identifier = String(req.body?.identifier ?? req.body?.email ?? "").trim().toLowerCase();
  const password = String(req.body?.password ?? "");
  const user = await User.findOne({ email: identifier, role: "CHILD" });
  if (!user || !(await verifyPassword(user.passwordHash, password))) {
    throw new AppError("Invalid child username or password", 401);
  }
  const token = signAccessToken({ sub: user.id, role: "CHILD" });
  const refreshToken = signRefreshToken({ sub: user.id, role: "CHILD", tokenVersion: user.refreshTokenVersion });
  res.json({ token, refreshToken, profile: profile(user) });
});

function childResponse(child: any, device: any) {
  return {
    id: child._id,
    name: child.name,
    username: child.email,
    email: child.email,
    device: device
      ? { id: device._id, deviceName: device.deviceName, platform: device.platform, status: device.status, lastSeen: device.lastSeen }
      : null,
    ...premium(child.expireDate),
  };
}

// GET /api/parent/childs - Seftly parent dashboard route.
export const seftlyParentChildren = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parent = await User.findOne({ _id: req.user!.id, role: "PARENT" }).lean();
  if (!parent) throw new AppError("Parent not found", 404);
  const requestedEmail = String(req.query.email ?? "").trim().toLowerCase();
  if (requestedEmail && requestedEmail !== parent.email) throw new AppError("You can only access your own children", 403);
  const children = await User.find({ role: "CHILD", parentId: parent._id }).lean();
  const results = await Promise.all(children.map(async (child) => childResponse(
    child,
    await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean(),
  )));
  res.json({ parent: { id: parent._id, name: parent.name, email: parent.email }, children: results, total: results.length, summary: { totalChildren: results.length, activeChildren: results.filter((child) => child.device?.status === "ONLINE").length } });
});

// GET /api/child - Parent-only child lookup with ownership enforcement.
export const seftlyGetChild = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const identifier = String(req.query.identifier ?? "").trim().toLowerCase();
  const child = await User.findOne({ role: "CHILD", email: identifier, parentId: req.user!.id }).lean();
  if (!child) throw new AppError("Child not found", 404);
  const device = await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean();
  res.json(childResponse(child, device));
});

// GET /api/child/lookup - Public identifier validation used before checkout.
export const seftlyLookupChild = asyncHandler(async (req: Request, res: Response) => {
  const identifier = String(req.query.identifier ?? "").trim().toLowerCase();
  const child = await User.findOne({ role: "CHILD", email: identifier }).lean();
  if (!child) throw new AppError("Child not found", 404);
  res.json({ valid: true, user: { id: child._id, name: child.name, username: child.email, email: child.email, ...premium(child.expireDate) } });
});

// GET /api/child/dashboard - Child dashboard route for the Seftly website.
export const seftlyChildDashboard = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const child = await User.findOne({ _id: req.user!.id, role: "CHILD" }).lean();
  if (!child) throw new AppError("Child not found", 404);
  const device = await Device.findOne({ childId: child._id }).sort({ updatedAt: -1 }).lean();
  res.json({ profile: { id: child._id, name: child.name, username: child.email, email: child.email }, device: { active: device?.status === "ONLINE", status: device?.status ?? "INACTIVE", message: device ? `${device.platform} device` : "No device registered." }, premium: premium(child.expireDate) });
});

// PATCH /api/account/email - Account settings used by the Seftly dashboard.
export const seftlyChangeEmail = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const newEmail = String(req.body?.newEmail ?? "").trim().toLowerCase();
  const currentPassword = String(req.body?.currentPassword ?? "");
  if (!newEmail || !newEmail.includes("@") || !currentPassword) throw new AppError("A valid email and current password are required", 400);
  const user = await User.findById(req.user!.id);
  if (!user || !(await verifyPassword(user.passwordHash, currentPassword))) throw new AppError("Current password is incorrect", 401);
  const existing = await User.findOne({ email: newEmail, _id: { $ne: user._id } });
  if (existing) throw new AppError("Email already in use", 409);
  user.email = newEmail;
  await user.save();
  res.json({ message: "Email changed successfully.", email: user.email });
});

// PATCH /api/account/password - Account settings used by the Seftly dashboard.
export const seftlyChangePassword = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const currentPassword = String(req.body?.currentPassword ?? "");
  const newPassword = String(req.body?.newPassword ?? "");
  const confirmPassword = String(req.body?.confirmPassword ?? "");
  if (!currentPassword || newPassword.length < 8 || newPassword !== confirmPassword) throw new AppError("Password fields are invalid", 400);
  const user = await User.findById(req.user!.id);
  if (!user || !(await verifyPassword(user.passwordHash, currentPassword))) throw new AppError("Current password is incorrect", 401);
  user.passwordHash = await hashPassword(newPassword);
  user.refreshTokenVersion += 1;
  await user.save();
  res.json({ message: "Password changed successfully." });
});

// Shared guard for private admin-dashboard synchronization routes.
export function requireSeftlyServiceToken(req: Request, _res: Response, next: () => void) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!env.serviceToken || token !== env.serviceToken) throw new AppError("Invalid service token", 401);
  next();
}

// GET /api/admin/parent-child - Data source for the Seftly admin Users page.
export const seftlyAdminParentChildren = asyncHandler(async (_req: Request, res: Response) => {
  const parents = await User.find({ role: "PARENT" }).lean();
  const result = await Promise.all(parents.map(async (parent) => {
    const children = await User.find({ role: "CHILD", parentId: parent._id }).lean();
    return {
      id: parent._id,
      name: parent.name,
      email: parent.email,
      children: children.map((child) => ({
        id: child._id,
        parentId: parent._id,
        name: child.name,
        username: child.email,
        email: child.email,
        ...premium(child.expireDate),
      })),
    };
  }));
  res.json({ parents: result });
});

// PATCH /api/child/:id/premium - Dashboard sync after local payment approval.
export const seftlySyncPremium = asyncHandler(async (req: Request, res: Response) => {
  const email = String(req.body?.email ?? "").trim().toLowerCase();
  const expireDate = new Date(String(req.body?.expireDate ?? ""));
  if (!email || Number.isNaN(expireDate.getTime())) throw new AppError("email and a valid expireDate are required", 400);
  const child = await User.findOne({ role: "CHILD", email });
  if (!child) throw new AppError("Child not found", 404);
  child.expireDate = expireDate;
  await child.save();
  res.json({ updated: true, id: child.id, ...premium(child.expireDate) });
});
