// Simple in-memory presence maps.
// For a single-instance VPS deployment this is fine. If you later scale to
// multiple Node processes, replace this with a Redis-backed adapter
// (e.g. @socket.io/redis-adapter) and store presence in Redis too.

const childSockets = new Map<string, Set<string>>(); // childId -> set of socketIds
const parentSockets = new Map<string, Set<string>>(); // parentId -> set of socketIds (parent may have multiple sessions)

export function setChildSocket(childId: string, socketId: string): void {
  const set = childSockets.get(childId) ?? new Set<string>();
  set.add(socketId);
  childSockets.set(childId, set);
}

export function removeChildSocket(childId: string, socketId: string): boolean {
  const set = childSockets.get(childId);
  if (!set) return true;
  set.delete(socketId);
  if (set.size === 0) {
    childSockets.delete(childId);
    return true;
  }
  return false;
}

export function getChildSocketIds(childId: string): string[] {
  return Array.from(childSockets.get(childId) ?? []);
}

export function getChildSocketId(childId: string): string | undefined {
  const set = childSockets.get(childId);
  if (!set || set.size === 0) return undefined;
  return Array.from(set)[set.size - 1];
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

export function getAllParentSocketIds(): string[] {
  const all: string[] = [];
  for (const set of parentSockets.values()) {
    all.push(...Array.from(set));
  }
  return all;
}

/** Find which childId (if any) owns a given socketId — used on disconnect. */
export function findChildIdBySocket(socketId: string): string | undefined {
  for (const [childId, set] of childSockets.entries()) {
    if (set.has(socketId)) return childId;
  }
  return undefined;
}
