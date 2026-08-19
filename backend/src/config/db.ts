import mongoose from "mongoose";
import { env } from "./env";

export async function connectDB(): Promise<void> {
  mongoose.set("strictQuery", true);
  await mongoose.connect(env.mongoUri);
  // eslint-disable-next-line no-console
  console.log(`[db] connected -> ${env.mongoUri}`);
}
