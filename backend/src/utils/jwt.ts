import jwt from "jsonwebtoken";
import { env } from "../config/env";

export interface AccessTokenPayload {
  sub: string; // user id
  role: "PARENT" | "CHILD";
}

export interface RefreshTokenPayload {
  sub: string;
  role: "PARENT" | "CHILD";
  tokenVersion: number;
}

export function signAccessToken(payload: AccessTokenPayload): string {
  return jwt.sign(payload, env.jwtAccessSecret, {
    expiresIn: env.jwtAccessExpiresIn,
  } as jwt.SignOptions);
}

export function signRefreshToken(payload: RefreshTokenPayload): string {
  return jwt.sign(payload, env.jwtRefreshSecret, {
    expiresIn: env.jwtRefreshExpiresIn,
  } as jwt.SignOptions);
}

export function verifyAccessToken(token: string): AccessTokenPayload {
  return jwt.verify(token, env.jwtAccessSecret) as AccessTokenPayload;
}

export function verifyRefreshToken(token: string): RefreshTokenPayload {
  return jwt.verify(token, env.jwtRefreshSecret) as RefreshTokenPayload;
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
  return jwt.verify(token, env.sessionTokenSecret) as {
    sessionId: string;
    userId: string;
    role: "PARENT" | "CHILD";
  };
}
