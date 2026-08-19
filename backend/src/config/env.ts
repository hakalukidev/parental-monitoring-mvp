import dotenv from "dotenv";
dotenv.config();

function required(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return v;
}

export const env = {
  port: parseInt(process.env.PORT || "4000", 10),
  nodeEnv: process.env.NODE_ENV || "development",
  corsOrigins: (process.env.CORS_ORIGINS || "http://localhost:3000")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean),

  mongoUri: required("MONGO_URI", "mongodb://127.0.0.1:27017/parental_monitoring"),

  jwtAccessSecret: required("JWT_ACCESS_SECRET"),
  jwtRefreshSecret: required("JWT_REFRESH_SECRET"),
  jwtAccessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || "15m",
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || "30d",

  sessionTokenSecret: required("SESSION_TOKEN_SECRET"),
  sessionTokenExpiresIn: process.env.SESSION_TOKEN_EXPIRES_IN || "10m",

  stunServers: (process.env.STUN_SERVERS || "stun:stun.l.google.com:19302")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean),
  turnUrl: process.env.TURN_URL,
  turnUsername: process.env.TURN_USERNAME,
  turnCredential: process.env.TURN_CREDENTIAL,
};
