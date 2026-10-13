import { z } from "zod";
import { objectIdSchema } from "../services/authorization";
import jwt from "jsonwebtoken";
import { env } from "../config/env";

export interface AccessTokenPayload {
  sub: string; // user id
  role: "PARENT" | "CHILD";
  tokenVersion?: number;
  exp?: number;
}

export interface RefreshTokenPayload {
  sub: string;
  role: "PARENT" | "CHILD";
  tokenVersion: number;
}

export function signAccessToken(payload: AccessTokenPayload): string {
  return jwt.sign({ ...payload, tokenVersion: payload.tokenVersion ?? 0 }, env.jwtAccessSecret, {
    expiresIn: env.jwtAccessExpiresIn,
  } as jwt.SignOptions);
}

export function signRefreshToken(payload: RefreshTokenPayload): string {
  return jwt.sign(payload, env.jwtRefreshSecret, {
    expiresIn: env.jwtRefreshExpiresIn,
  } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  return z.object({ sub: objectIdSchema, role: z.enum(["PARENT", "CHILD"]), tokenVersion: z.number().int().nonnegative().optional(), exp: z.number().int() }).parse(jwt.verify(token, env.jwtAccessSecret, { algorithms: ["HS256"] }));
}

export function verifyRefreshToken(token: string): RefreshTokenPayload {
  return z.object({ sub: objectIdSchema, role: z.enum(["PARENT", "CHILD"]), tokenVersion: z.number().int().nonnegative() }).parse(jwt.verify(token, env.jwtRefreshSecret, { algorithms: ["HS256"] }));
}

/** Short-lived token handed to the Parent/Child app to authorize a single WebRTC session's signaling. */
export function signSessionToken(payload: {
  sessionId: string;
  userId: string;
  role: "PARENT" | "CHILD";
}): string {
  return jwt.sign(payload, env.sessionTokenSecret, {
    expiresIn: env.sessionTokenExpiresIn,
  } as jwt.SignOptions);
}

export function verifySessionToken(token: string): {
  sessionId: string;
  userId: string;
  role: "PARENT" | "CHILD";
} {
  return jwt.verify(token, env.sessionTokenSecret, { algorithms: ["HS256"] }) as {
    sessionId: string;
    userId: string;
    role: "PARENT" | "CHILD";
  };
}
