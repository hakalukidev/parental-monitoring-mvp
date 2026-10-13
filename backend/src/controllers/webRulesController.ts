import { Response } from "express";
import { asyncHandler, AppError } from "../utils/http";
import { AuthedRequest } from "../middleware/auth";
import { assertParentOwnsChild } from "./childrenController";
import { WebBlockRule } from "../models/WebBlockRule";
import { getIO } from "../socket/io";
import { getChildSocketIds } from "../socket/presence";
import { createWebRuleSchema, updateWebRuleSchema } from "../utils/validation";
import { normalizeWebsiteTarget, WebsiteRuleType } from "../services/webTargets";
import { Device } from "../models/Device";

function normalized(type: WebsiteRuleType, target: string) {
  try { return normalizeWebsiteTarget(type, target); }
  catch (error) { throw new AppError(error instanceof Error ? error.message : "Invalid website address", 422); }
}

export const previewWebRule = asyncHandler(async (req: AuthedRequest, res: Response) => {
  await assertParentOwnsChild(req.user!.id, req.params.childId);
  const data = createWebRuleSchema.parse(req.body);
  const target = normalized(data.ruleType, data.target);
  const device = await Device.findOne({ childId: req.params.childId }).sort({ updatedAt: -1 }).select("policyProtocolVersion").lean();
  res.json({ ...target, requiresChildUpdate: target.ruleType === "URL" && device?.policyProtocolVersion !== 2 });
});

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
  const target = normalized(data.ruleType, data.target);
  if (target.ruleType === "URL" && (await Device.findOne({childId}).sort({updatedAt:-1}).select("policyProtocolVersion").lean())?.policyProtocolVersion !== 2) throw new AppError("Update Seftly Child before applying exact URL rules",409);

  const rule = await WebBlockRule.create({
    childId,
    ...target,
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
  } catch { console.error("[socket] update delivery unavailable; clients must resynchronize"); }

  res.status(201).json({ rule });
});

// PUT /api/children/:childId/web-rules/:ruleId (Parent only)
export const updateWebRule = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const parentId = req.user!.id;
  const { childId, ruleId } = req.params;
  await assertParentOwnsChild(parentId, childId);

  const data = updateWebRuleSchema.parse(req.body);

  const existing = await WebBlockRule.findOne({ _id: ruleId, childId });
  if (!existing) throw new AppError("Web rule not found", 404);
  const targetChange = data.target !== undefined || data.ruleType !== undefined
    ? normalized(data.ruleType ?? existing.ruleType, data.target ?? existing.target) : {};
  if ("ruleType" in targetChange && targetChange.ruleType === "URL" && (await Device.findOne({childId}).sort({updatedAt:-1}).select("policyProtocolVersion").lean())?.policyProtocolVersion !== 2) throw new AppError("Update Seftly Child before applying exact URL rules",409);
  const rule = await WebBlockRule.findOneAndUpdate(
    { _id: ruleId, childId },
    { $set: { ...data, ...targetChange } },
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
  } catch { console.error("[socket] update delivery unavailable; clients must resynchronize"); }

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
  } catch { console.error("[socket] update delivery unavailable; clients must resynchronize"); }

  res.json({ success: true, message: "Rule deleted" });
});

// GET /api/children/my-web-rules (Child only)
export const getMyWebRules = asyncHandler(async (req: AuthedRequest, res: Response) => {
  const childId = req.user!.id;
  const rules = await WebBlockRule.find({ childId, isEnabled: true }).lean();
  res.json({ rules });
});
