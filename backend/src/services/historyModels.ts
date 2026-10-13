import { Schema } from "mongoose";
/** Index application is an operator task in production (autoIndex is disabled). */
export function addRetention(schema: Schema): void {
  schema.add({ expiresAt: { type: Date, default: null } });
  schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
}
