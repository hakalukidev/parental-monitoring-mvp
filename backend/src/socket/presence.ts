// Simple in-memory presence maps.
// For a single-instance VPS deployment this is fine. If you later scale to
// multiple Node processes, replace this with a Redis-backed adapter
// (e.g. @socket.io/redis-adapter) and store presence in Redis too.

const childSockets = new Map<string, string>(); // childId -> socketId
const parentSockets = new Map<string, Set<string>>(); // parentId -> set of socketIds (parent may have multiple sessions)

export function setChildSocket(childId: string, socketId: string): void {
  childSockets.set(childId, socketId);
}

export function removeChildSocket(childId: string): void {
  childSockets.delete(childId);
}

export function getChildSocketId(childId: string): string | undefined {
  return childSockets.get(childId);
}

export function addParentSocket(parentId: string, socketId: string): void {
  const set = parentSockets.get(parentId) ?? new Set<string>();
  set.add(socketId);
  parentSockets.set(parentId, set);
}

export function removeParentSocket(parentId: string, socketId: string): void {
  const set = parentSockets.get(parentId);
  if (!set) return;
  set.delete(socketId);
  if (set.size === 0) parentSockets.delete(parentId);
}

export function getParentSocketIds(parentId: string): string[] {
  return Array.from(parentSockets.get(parentId) ?? []);
}

/** Find which childId (if any) owns a given socketId — used on disconnect. */
export function findChildIdBySocket(socketId: string): string | undefined {
  for (const [childId, sId] of childSockets.entries()) {
    if (sId === socketId) return childId;
  }
  return undefined;
}
