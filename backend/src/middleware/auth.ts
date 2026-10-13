import { User } from "../models/User";
import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";
import { AppError } from "../utils/http";

export interface AuthedRequest extends Request {
  user?: {
    id: string;
    role: "PARENT" | "CHILD";
  };
}

export function requireAuth(req: AuthedRequest, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    throw new AppError("Missing or invalid Authorization header", 401);
  }
  const token = header.slice("Bearer ".length);
  void (async () => {
    let payload;
    try { payload = verifyAccessToken(token); } catch { throw new AppError("Invalid or expired access token", 401); }
    const user = await User.findById(payload.sub);
    if (!user || user.role !== payload.role || user.refreshTokenVersion !== (payload.tokenVersion ?? 0)) throw new AppError("Session expired; please sign in again", 401);
    req.user = { id: user.id, role: user.role };
  })().then(() => next(), next);
}

export function requireRole(role: "PARENT" | "CHILD") {
  return (req: AuthedRequest, _res: Response, next: NextFunction): void => {
    if (!req.user || req.user.role !== role) {
      throw new AppError("Forbidden: insufficient role", 403);
    }
    next();
  };
}
