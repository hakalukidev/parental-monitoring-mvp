import privacyRoutes from "./routes/privacyRoutes";
import mongoose from "mongoose";
import rateLimit from "express-rate-limit";
import express, { Express } from "express";
import cors from "cors";
import helmet from "helmet";
import cookieParser from "cookie-parser";
import { env } from "./config/env";
import { errorHandler } from "./middleware/errorHandler";

import authRoutes from "./routes/authRoutes";
import childrenRoutes from "./routes/childrenRoutes";
import deviceRoutes from "./routes/deviceRoutes";
import screenShareRoutes from "./routes/screenShareRoutes";
import cameraStreamRoutes from "./routes/cameraStreamRoutes";
import configRoutes from "./routes/configRoutes";
import locationRoutes from "./routes/locationRoutes";
import appPolicyRoutes from "./routes/appPolicyRoutes";
import webRulesRoutes from "./routes/webRulesRoutes";
import browsingHistoryRoutes from "./routes/browsingHistoryRoutes";
import geofenceRoutes from "./routes/geofenceRoutes";
import appUsageRoutes from "./routes/appUsageRoutes";
import seftlyRoutes from "./routes/seftlyRoutes";

export function createApp(): Express {
  const app = express();

  app.set("trust proxy", Number(process.env.TRUST_PROXY_HOPS ?? 0));
  app.disable("x-powered-by");
  app.use("/api", rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true, legacyHeaders: false }));

  app.use(helmet());
  app.use(
    cors({
      origin: env.corsOrigins,
      credentials: true,
    })
  );
  app.use(express.json({ limit: "1mb" }));
  app.use(cookieParser());

  app.get("/health", (_req, res) => res.json({ status: "ok", time: new Date().toISOString() }));

  app.get("/ready", (_req, res) => res.status(mongoose.connection.readyState === 1 ? 200 : 503).json({ status: mongoose.connection.readyState === 1 ? "ready" : "unavailable", revision: process.env.RELEASE_REVISION ?? "development" }));

  app.use("/api/auth", authRoutes);
  app.use("/api/children", privacyRoutes);
  app.use("/api/children", appPolicyRoutes);
  app.use("/api/children", webRulesRoutes);
  app.use("/api/children", browsingHistoryRoutes);
  app.use("/api/children", geofenceRoutes);
  app.use("/api/children", appUsageRoutes);
  app.use("/api/children", childrenRoutes);
  app.use("/api/devices", deviceRoutes);
  app.use("/api/screen-share", screenShareRoutes);
  app.use("/api/camera-stream", cameraStreamRoutes);
  app.use("/api/location", locationRoutes);
  app.use("/api/config", configRoutes);
  app.use("/api", seftlyRoutes);

  app.use((req, res) => {
    res.status(404).json({ error: `Not found: ${req.method} ${req.originalUrl}` });
  });

  app.use(errorHandler);

  return app;
}
