import { Geofence, IGeofence } from "../models/Geofence";
import { GeofenceEvent } from "../models/GeofenceEvent";
import { User } from "../models/User";
import { getIO } from "../socket/io";
import { getParentSocketIds } from "../socket/presence";

/**
 * Calculates great-circle distance between two points in meters using Haversine formula.
 */
export function calculateHaversineDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371000; // Earth's radius in meters
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Checks if the geofence schedule is active at a given date/time.
 */
export function isScheduleActive(
  schedule: IGeofence["schedule"] | undefined,
  date: Date
): boolean {
  if (!schedule) return true;

  // Day of week check (0 = Sun, 1 = Mon ... 6 = Sat)
  const currentDay = date.getDay();
  if (schedule.daysOfWeek && schedule.daysOfWeek.length > 0) {
    if (!schedule.daysOfWeek.includes(currentDay)) {
      return false;
    }
  }

  // Time window check (HH:mm)
  if (schedule.startTime && schedule.endTime) {
    const hours = date.getHours().toString().padStart(2, "0");
    const minutes = date.getMinutes().toString().padStart(2, "0");
    const currentTimeStr = `${hours}:${minutes}`;

    if (schedule.startTime <= schedule.endTime) {
      if (currentTimeStr < schedule.startTime || currentTimeStr > schedule.endTime) {
        return false;
      }
    } else {
      // Over-midnight window (e.g. 22:00 to 06:00)
      if (currentTimeStr < schedule.startTime && currentTimeStr > schedule.endTime) {
        return false;
      }
    }
  }

  return true;
}

export interface LocationPayload {
  latitude: number;
  longitude: number;
  accuracy?: number;
  altitude?: number;
  speed?: number;
  heading?: number;
  batteryLevel?: number;
  recordedAt?: Date | string;
}

/**
 * Core Geofencing Evaluation Engine.
 * Evaluates a child's location against all active geofences and emits instant alerts on boundary crossing.
 */
export async function evaluateChildGeofences(
  childId: string,
  parentId: string,
  location: LocationPayload
): Promise<void> {
  try {
    // 1. Accuracy Filter: Ignore fixes with excessive horizontal error (e.g. > 45m)
    if (location.accuracy && location.accuracy > 45) {
      return;
    }

    const recordedDate = location.recordedAt
      ? new Date(location.recordedAt)
      : new Date();

    // 2. Fetch all active geofences for this child
    const geofences = await Geofence.find({
      childId,
      isEnabled: true,
    });

    if (geofences.length === 0) return;

    let childName = "";
    const childUser = await User.findById(childId).select("name");
    if (childUser) {
      childName = childUser.name;
    }

    for (const geofence of geofences) {
      // Schedule check
      if (!isScheduleActive(geofence.schedule, recordedDate)) {
        continue;
      }

      const distance = calculateHaversineDistance(
        geofence.latitude,
        geofence.longitude,
        location.latitude,
        location.longitude
      );

      // Adaptive hysteresis buffer based on location accuracy
      const accuracyMargin = location.accuracy ? Math.min(25, location.accuracy * 0.5) : 15;
      const buffer = Math.max(10, accuracyMargin);

      let currentState: "INSIDE" | "OUTSIDE";
      if (distance <= geofence.radius - buffer) {
        currentState = "INSIDE";
      } else if (distance > geofence.radius + buffer) {
        currentState = "OUTSIDE";
      } else {
        // In the buffer band: retain previous state to prevent boundary jitter
        currentState =
          geofence.lastState === "UNKNOWN"
            ? distance <= geofence.radius
              ? "INSIDE"
              : "OUTSIDE"
            : geofence.lastState;
      }

      const previousState = geofence.lastState;
      const isInitialCheck = previousState === "UNKNOWN";
      const isStateChanged = previousState !== currentState;

      let shouldTrigger = false;
      let transitionType: "EXIT" | "ENTRY" = "ENTRY";
      let alertTitle = "";
      let alertBody = "";

      const TRANSITION_COOLDOWN_MS = 60 * 1000; // 1 minute cooldown for transition bouncing
      const SUSTAINED_COOLDOWN_MS = 15 * 60 * 1000; // 15 minutes cooldown for sustained violation

      const timeSinceLastTrigger = geofence.lastTriggeredAt
        ? recordedDate.getTime() - geofence.lastTriggeredAt.getTime()
        : Infinity;

      const timeString = recordedDate.toLocaleTimeString("en-US", {
        hour: "numeric",
        minute: "2-digit",
        hour12: true,
      });

      if (isInitialCheck) {
        // Child's location is evaluated for the first time or after state reset
        if (geofence.zoneType === "RESTRICTED_ZONE") {
          if (currentState === "INSIDE") {
            // Child is currently inside a restricted zone!
            transitionType = "ENTRY";
            shouldTrigger =
              geofence.triggerType === "ENTRY" ||
              geofence.triggerType === "BOTH";
            alertTitle = `⚠️ Restricted Zone Alert: ${geofence.name}`;
            alertBody = `${childName || "Child"} is currently inside restricted zone ${geofence.name} (detected at ${timeString}). Tap to view route trail.`;
          }
        } else {
          // SAFE_ZONE
          if (currentState === "OUTSIDE") {
            // Child is currently outside the safe zone!
            transitionType = "EXIT";
            shouldTrigger =
              geofence.triggerType === "EXIT" ||
              geofence.triggerType === "BOTH";
            alertTitle = `🚨 Safe Zone Alert: ${geofence.name}`;
            alertBody = `${childName || "Child"} is currently outside safe zone ${geofence.name} (detected at ${timeString}). Tap to view route trail.`;
          } else if (currentState === "INSIDE") {
            // Child is currently inside safe zone
            if (
              geofence.triggerType === "ENTRY" ||
              geofence.triggerType === "BOTH"
            ) {
              transitionType = "ENTRY";
              shouldTrigger = true;
              alertTitle = `✅ Safe Zone Reached: ${geofence.name}`;
              alertBody = `${childName || "Child"} is currently inside safe zone ${geofence.name} (detected at ${timeString}). Tap to view route trail.`;
            }
          }
        }
      } else if (isStateChanged) {
        // Child crossed the boundary
        transitionType =
          previousState === "INSIDE" && currentState === "OUTSIDE" ? "EXIT" : "ENTRY";

        const matchesTrigger =
          geofence.triggerType === "BOTH" ||
          geofence.triggerType === transitionType ||
          (geofence.zoneType === "SAFE_ZONE" && transitionType === "EXIT") ||
          (geofence.zoneType === "RESTRICTED_ZONE" && transitionType === "ENTRY");

        if (matchesTrigger && timeSinceLastTrigger > TRANSITION_COOLDOWN_MS) {
          shouldTrigger = true;
          if (geofence.zoneType === "RESTRICTED_ZONE") {
            alertTitle =
              transitionType === "ENTRY"
                ? `⚠️ Restricted Zone Entered: ${geofence.name}`
                : `🛡️ Restricted Zone Exited: ${geofence.name}`;
            alertBody = `${childName || "Child"} ${transitionType === "ENTRY" ? "entered" : "left"} restricted zone ${geofence.name} at ${timeString}. Tap to view route trail.`;
          } else {
            alertTitle =
              transitionType === "EXIT"
                ? `🚨 Safe Zone Left: ${geofence.name}`
                : `✅ Safe Zone Reached: ${geofence.name}`;
            alertBody = `${childName || "Child"} ${transitionType === "EXIT" ? "left" : "entered"} safe zone ${geofence.name} at ${timeString}. Tap to view route trail.`;
          }
        }
      } else {
        // Child is still in the same state (Sustained state violation check)
        const isRestrictedViolation =
          geofence.zoneType === "RESTRICTED_ZONE" && currentState === "INSIDE";
        const isSafeZoneViolation =
          geofence.zoneType === "SAFE_ZONE" &&
          currentState === "OUTSIDE" &&
          (geofence.triggerType === "EXIT" || geofence.triggerType === "BOTH");

        if (
          (isRestrictedViolation || isSafeZoneViolation) &&
          timeSinceLastTrigger > SUSTAINED_COOLDOWN_MS
        ) {
          shouldTrigger = true;
          if (isRestrictedViolation) {
            transitionType = "ENTRY";
            alertTitle = `⚠️ Ongoing Restricted Zone Alert: ${geofence.name}`;
            alertBody = `${childName || "Child"} is still inside restricted zone ${geofence.name} (detected at ${timeString}). Tap to view route trail.`;
          } else {
            transitionType = "EXIT";
            alertTitle = `🚨 Ongoing Safe Zone Alert: ${geofence.name}`;
            alertBody = `${childName || "Child"} is still outside safe zone ${geofence.name} (detected at ${timeString}). Tap to view route trail.`;
          }
        }
      }

      // Update state tracking on geofence
      geofence.lastState = currentState;
      if (isStateChanged || isInitialCheck) {
        geofence.lastStateChangedAt = recordedDate;
      }

      if (shouldTrigger) {
        geofence.lastTriggeredAt = recordedDate;
        await geofence.save();

        const message = alertBody;

        // Create persistent GeofenceEvent in MongoDB
        const event = await GeofenceEvent.create({
          parentId,
          childId,
          geofenceId: geofence._id,
          geofenceName: geofence.name,
          eventType: transitionType,
          zoneType: geofence.zoneType,
          title: alertTitle,
          body: alertBody,
          latitude: location.latitude,
          longitude: location.longitude,
          accuracy: location.accuracy,
          speed: location.speed,
          distanceFromCenter: Math.round(distance),
          geofenceRadius: geofence.radius,
          address: geofence.address || "",
          isRead: false,
          isNotified: false,
          triggeredAt: recordedDate,
        });

        // Broadcast instant alert via Socket.IO to connected parent sockets
        try {
          const io = getIO();
          const parentSocketIds = getParentSocketIds(parentId);
          for (const socketId of parentSocketIds) {
            io.to(socketId).emit("geofence_alert", {
              eventId: event._id.toString(),
              childId,
              childName: childName || "Child",
              geofenceId: geofence._id.toString(),
              geofenceName: geofence.name,
              eventType: transitionType,
              zoneType: geofence.zoneType,
              title: alertTitle,
              body: alertBody,
              message,
              latitude: location.latitude,
              longitude: location.longitude,
              accuracy: location.accuracy,
              speed: location.speed,
              distanceFromCenter: Math.round(distance),
              geofenceRadius: geofence.radius,
              address: geofence.address,
              triggeredAt: recordedDate.toISOString(),
              location: {
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy,
                speed: location.speed,
                distanceFromCenter: Math.round(distance),
                geofenceRadius: geofence.radius,
                recordedAt: recordedDate.toISOString(),
              },
            });
          }
        } catch (socketErr) {
          console.error("Failed to emit geofence_alert socket event:", socketErr);
        }
      } else {
        await geofence.save();
      }
    }
  } catch (err) {
    console.error("Error evaluating geofences:", err);
  }
}
