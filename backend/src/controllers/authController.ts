import { Request, Response } from "express";
import { User } from "../models/User";
import { hashPassword, verifyPassword } from "../utils/password";
import { signAccessToken, signRefreshToken, verifyRefreshToken } from "../utils/jwt";
import { asyncHandler, AppError } from "../utils/http";
import { registerParentSchema, loginSchema, childLoginSchema } from "../utils/validation";
import { AuthedRequest } from "../middleware/auth";

const REFRESH_COOKIE = "refresh_token";
const isProd = process.env.NODE_ENV === "production";

function setRefreshCookie(res: Response, token: string) {
  res.cookie(REFRESH_COOKIE, token, {
    httpOnly: true,
    secure: isProd,
    sameSite: "strict",
    path: "/api/auth",
    maxAge: 30 * 24 * 60 * 60 * 1000, // 30 days
  });
}

export const register = asyncHandler(async (req: Request, res: Response) => {
  const data = registerParentSchema.parse(req.body);

  const existing = await User.findOne({ email: data.email.toLowerCase() });
  if (existing) throw new AppError("Email already in use", 409);

  const passwordHash = await hashPassword(data.password);
  const user = await User.create({
    name: data.name,
    email: data.email.toLowerCase(),
    passwordHash,
    role: "PARENT",
  });

  const accessToken = signAccessToken({ sub: user.id, role: "PARENT" });
  const refreshToken = signRefreshToken({ sub: user.id, role: "PARENT", tokenVersion: user.refreshTokenVersion });
  setRefreshCookie(res, refreshToken);

  res.status(201).json({
    accessToken,
    user: { id: user.id, name: user.name, email: user.email, role: user.role },
  });
});

export const login = asyncHandler(async (req: Request, res: Response) => {
  const data = loginSchema.parse(req.body);

  const user = await User.findOne({ email: data.email.toLowerCase() });
  if (!user) throw new AppError("Invalid email or password", 401);

  const ok = await verifyPassword(user.passwordHash, data.password);
  if (!ok) throw new AppError("Invalid email or password", 401);

  const accessToken = signAccessToken({ sub: user.id, role: user.role });
  const refreshToken = signRefreshToken({
    sub: user.id,
    role: user.role,
    tokenVersion: user.refreshTokenVersion,
  });
  setRefreshCookie(res, refreshToken);

  res.json({
    accessToken,
    user: { id: user.id, name: user.name, email: user.email, role: user.role },
  });
});

export const refresh = asyncHandler(async (req: Request, res: Response) => {
  const token = req.cookies?.[REFRESH_COOKIE];
  if (!token) throw new AppError("Missing refresh token", 401);

  let payload;
  try {
    payload = verifyRefreshToken(token);
  } catch {
    throw new AppError("Invalid or expired refresh token", 401);
  }

  const user = await User.findById(payload.sub);
  if (!user || user.refreshTokenVersion !== payload.tokenVersion) {
    throw new AppError("Refresh token has been revoked", 401);
  }

  const accessToken = signAccessToken({ sub: user.id, role: user.role });
  res.json({ accessToken });
});

export const logout = asyncHandler(async (req: AuthedRequest, res: Response) => {
  // Invalidate all refresh tokens for this user (bump version) and clear cookie
  if (req.user) {
    await User.findByIdAndUpdate(req.user.id, { $inc: { refreshTokenVersion: 1 } });
  }
  res.clearCookie(REFRESH_COOKIE, { path: "/api/auth" });
  res.status(204).send();
});

export const childLogin = asyncHandler(async (req: Request, res: Response) => {
  const data = childLoginSchema.parse(req.body);

  const user = await User.findOne({ email: data.email.toLowerCase(), role: "CHILD" });
  if (!user) throw new AppError("Invalid username or password", 401);

  const ok = await verifyPassword(user.passwordHash, data.password);
  if (!ok) throw new AppError("Invalid username or password", 401);

  const accessToken = signAccessToken({ sub: user.id, role: "CHILD" });
  const refreshToken = signRefreshToken({
    sub: user.id,
    role: "CHILD",
    tokenVersion: user.refreshTokenVersion,
  });
  setRefreshCookie(res, refreshToken);

  res.json({
    accessToken,
    user: { id: user.id, name: user.name, username: user.email, role: user.role, parentId: user.parentId },
  });
});
