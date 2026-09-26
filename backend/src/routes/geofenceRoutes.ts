import { Router } from "express";
import {
  createGeofence,
  listGeofences,
  getGeofence,
  updateGeofence,
  deleteGeofence,
  toggleGeofence,
  listGeofenceEvents,
  markEventRead,
  markAllEventsRead,
  getMyGeofences,
  getUnreadGeofenceEventsSummary,
} from "../controllers/geofenceController";
import { requireAuth, requireRole } from "../middleware/auth";

const router = Router();

// Child endpoint to sync geofences
router.get("/my-geofences", requireAuth, requireRole("CHILD"), getMyGeofences);

// Parent catch-up unread events summary across all children (must precede :childId)
router.get("/geofence-events/unread-summary", requireAuth, requireRole("PARENT"), getUnreadGeofenceEventsSummary);

// Parent geofence CRUD routes
router.post("/:childId/geofences", requireAuth, requireRole("PARENT"), createGeofence);
router.get("/:childId/geofences", requireAuth, requireRole("PARENT"), listGeofences);
router.get("/:childId/geofences/:id", requireAuth, requireRole("PARENT"), getGeofence);
router.put("/:childId/geofences/:id", requireAuth, requireRole("PARENT"), updateGeofence);
router.delete("/:childId/geofences/:id", requireAuth, requireRole("PARENT"), deleteGeofence);
router.patch("/:childId/geofences/:id/toggle", requireAuth, requireRole("PARENT"), toggleGeofence);

// Parent geofence alert event logs
router.get("/:childId/geofence-events", requireAuth, requireRole("PARENT"), listGeofenceEvents);
router.patch("/:childId/geofence-events/:id/read", requireAuth, requireRole("PARENT"), markEventRead);
router.patch("/:childId/geofence-events/mark-all-read", requireAuth, requireRole("PARENT"), markAllEventsRead);

export default router;
