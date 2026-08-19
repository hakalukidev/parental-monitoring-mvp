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
import configRoutes from "./routes/configRoutes";

export function createApp(): Express {
  const app = express();

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

  app.use("/api/auth", authRoutes);
  app.use("/api/children", childrenRoutes);
  app.use("/api/devices", deviceRoutes);
  app.use("/api/screen-share", screenShareRoutes);
  app.use("/api/config", configRoutes);

  app.use((req, res) => {
    res.status(404).json({ error: `Not found: ${req.method} ${req.originalUrl}` });
  });

  app.use(errorHandler);

  return app;
}
