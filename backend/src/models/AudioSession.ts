import { model } from "mongoose";
import { ScreenShareSession, IScreenShareSession } from "./ScreenShareSession";

// Reuse the participant, negotiation and expiry contract; this session has no video or recording.
export const AudioSession = model<IScreenShareSession>("AudioSession", ScreenShareSession.schema.clone());
