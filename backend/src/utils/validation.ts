import { z } from "zod";

export const registerParentSchema = z
  .object({
    name: z.string().min(2).max(100),
    email: z.string().email(),
    password: z.string().min(8).max(128),
    confirmPassword: z.string().min(8).max(128),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export const childLoginSchema = z.object({
  email: z.string().min(3), // child logs in with username, not necessarily an email
  password: z.string().min(1),
});

export const createChildSchema = z
  .object({
    name: z.string().min(2).max(100),
    username: z.string().min(3).max(50), // stored as email field internally (username@child.local pattern not required; we store raw as unique login id)
    password: z.string().min(8).max(128),
    confirmPassword: z.string().min(8).max(128),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: "Passwords do not match",
    path: ["confirmPassword"],
  });

export const registerDeviceSchema = z.object({
  deviceName: z.string().min(1).max(100),
  platform: z.string().min(1).max(50).default("Android"),
});

export const screenShareRequestSchema = z.object({
  childId: z.string().min(1),
});

export const cameraStreamRequestSchema = z.object({
  childId: z.string().min(1),
  cameraFacing: z.enum(["BACK", "FRONT"]).default("BACK"),
  withAudio: z.boolean().default(true),
});

export const recordLocationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracy: z.number().nonnegative().optional(),
  altitude: z.number().optional(),
  speed: z.number().nonnegative().optional(),
  heading: z.number().min(0).max(360).optional(),
  batteryLevel: z.number().min(0).max(100).optional(),
  recordedAt: z.string().or(z.date()).optional(),
});

export const recordLocationBatchSchema = z.object({
  points: z.array(recordLocationSchema).min(1).max(500),
});

export const locationHistoryQuerySchema = z.object({
  startTime: z.string().optional(),
  endTime: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(2000).default(500),
});


