import mongoose from "mongoose";
import { env } from "./env";

export async function connectDB(): Promise<void> {
  mongoose.set("strictQuery", true);
  await mongoose.connect(env.mongoUri, { autoIndex: env.nodeEnv !== "production", serverSelectionTimeoutMS: 10000 });
  // eslint-disable-next-line no-console
  console.log("[db] connected");
}
