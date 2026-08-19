import { Server } from "socket.io";

let ioInstance: Server | null = null;

export function setIO(io: Server): void {
  ioInstance = io;
}

export function getIO(): Server {
  if (!ioInstance) throw new Error("Socket.IO server has not been initialized yet");
  return ioInstance;
}
