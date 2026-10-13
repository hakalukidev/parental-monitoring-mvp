export type Feature = "AUDIO" | "NOTIFICATIONS" | "CALL_SMS" | "SAFETY" | "COMMUNICATIONS";
export function featureEnabled(feature: Feature): boolean { return process.env[`FEATURE_${feature}_ENABLED`] === "true"; }
