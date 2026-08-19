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
  try {
    const payload = verifyAccessToken(token);
    req.user = { id: payload.sub, role: payload.role };
    next();
  } catch {
    throw new AppError("Invalid or expired access token", 401);
  }
}

export function requireRole(role: "PARENT" | "CHILD") {
  return (req: AuthedRequest, _res: Response, next: NextFunction): void => {
    if (!req.user || req.user.role !== role) {
      throw new AppError("Forbidden: insufficient role", 403);
    }
    next();
  };
}
