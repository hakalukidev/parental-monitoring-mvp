import { Request, Response, NextFunction } from "express";
import { AppError } from "../utils/http";
import { ZodError } from "zod";

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof ZodError) {
    res.status(422).json({
      error: "ValidationError",
      details: err.issues.map((i) => ({ path: i.path.join("."), message: i.message })),
    });
    return;
  }

  if (err instanceof AppError) {
    res.status(err.statusCode).json({ error: err.message });
    return;
  }

  // eslint-disable-next-line no-console
  console.error("[unhandled error]", err);
  res.status(500).json({ error: "Internal server error" });
}
