import { Response } from "express";
import { asyncHandler, AppError } from "../utils/http";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { WebBlockRule } from "../models/WebBlockRule";
import { getIO } from "../socket/io";
import { getChildSocketIds } from "../socket/presence";
import { createWebRuleSchema, updateWebRuleSchema } from "../utils/validation";

// GET /api/children/:childId/web-rules (Parent only)
export const listWebRules = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  const rules = await WebBlockRule.find({ childId }).sort({ createdAt: -1 }).lean();
  res.json({ rules });
});

// POST /api/children/:childId/web-rules (Parent only)
export const createWebRule = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const childId = req.params.childId;
  await assertParentOwnsChild(parentId, childId);

  const data = createWebRuleSchema.parse(req.body);

  const rule = await WebBlockRule.create({
    childId,
    ruleType: data.ruleType,
    target: data.target.toLowerCase().trim(),
    action: data.action,
    isEnabled: data.isEnabled,
  });

  // Notify child via socket
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("policy_updated", {
        type: "WEB_RULE_ADDED",
        rule,
      });
    }
  } catch {}

  res.status(201).json({ rule });
});

// PUT /api/children/:childId/web-rules/:ruleId (Parent only)
export const updateWebRule = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, ruleId } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const data = updateWebRuleSchema.parse(req.body);

  const rule = await WebBlockRule.findOneAndUpdate(
    { _id: ruleId, childId },
    { $set: data },
    { new: true }
  );
  if (!rule) throw new AppError("Web rule not found", 404);

  // Notify child via socket
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("policy_updated", {
        type: "WEB_RULE_UPDATED",
        rule,
      });
    }
  } catch {}

  res.json({ rule });
});

// DELETE /api/children/:childId/web-rules/:ruleId (Parent only)
export const deleteWebRule = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, ruleId } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const rule = await WebBlockRule.findOneAndDelete({ _id: ruleId, childId });
  if (!rule) throw new AppError("Web rule not found", 404);

  // Notify child via socket
  try {
    const io = getIO();
    for (const socketId of getChildSocketIds(childId)) {
      io.to(socketId).emit("policy_updated", {
        type: "WEB_RULE_DELETED",
        ruleId,
      });
    }
  } catch {}

  res.json({ success: true, message: "Rule deleted" });
});

// GET /api/children/my-web-rules (Child only)
export const getMyWebRules = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;
  const rules = await WebBlockRule.find({ childId, isEnabled: true }).lean();
  res.json({ rules });
});
