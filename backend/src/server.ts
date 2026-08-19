import http from "http";
import { Server } from "socket.io";
import { createApp } from "./app";
import { connectDB } from "./config/db";
import { env } from "./config/env";
import { setIO } from "./socket/io";
import { registerSocketHandlers } from "./socket";

async function main() {
  await connectDB();

  const app = createApp();
  const httpServer = http.createServer(app);

  const io = new Server(httpServer, {
    cors: {
      origin: env.corsOrigins,
      credentials: true,
    },
  });
  setIO(io);
  registerSocketHandlers(io);

  httpServer.listen(env.port, () => {
    // eslint-disable-next-line no-console
    console.log(`[server] listening on port ${env.port} (${env.nodeEnv})`);
  });

  const shutdown = () => {
    // eslint-disable-next-line no-console
    console.log("[server] shutting down...");
    httpServer.close(() => process.exit(0));
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error("[server] fatal startup error", err);
  process.exit(1);
});
