import { createCipheriv, createDecipheriv, createHmac, randomBytes } from "node:crypto";

export function communicationKeyAvailable(): boolean { return /^[a-f\d]{64}$/i.test(process.env.COMMUNICATION_DATA_KEY ?? ""); }
function key(): Buffer {
  if (!communicationKeyAvailable()) throw new Error("Communication encryption is unavailable");
  return Buffer.from(process.env.COMMUNICATION_DATA_KEY!, "hex");
}
export function communicationDigest(domain: string, value: string): string { return createHmac("sha256", key()).update(domain + "\0" + value).digest("hex"); }
export function sealCommunication(identity: string, value: unknown): string {
  const iv = randomBytes(12), cipher = createCipheriv("aes-256-gcm", key(), iv);
  cipher.setAAD(Buffer.from(identity));
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return ["v1", iv.toString("base64url"), cipher.getAuthTag().toString("base64url"), encrypted.toString("base64url")].join(".");
}
export function openCommunication(identity: string, sealed: string): Record<string, unknown> {
  const [version, encodedIv, encodedTag, encodedData, extra] = sealed.split(".");
  if (version !== "v1" || extra !== undefined) throw new Error("Invalid encrypted communication");
  const iv = Buffer.from(encodedIv, "base64url"), tag = Buffer.from(encodedTag, "base64url");
  if (iv.length !== 12 || tag.length !== 16) throw new Error("Invalid encrypted communication");
  const decipher = createDecipheriv("aes-256-gcm", key(), iv);
  decipher.setAAD(Buffer.from(identity)); decipher.setAuthTag(tag);
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(encodedData, "base64url")), decipher.final()]).toString("utf8"));
}
// Conservative suppression, not a promise to recognize every possible security secret.
export function securityMessage(body: string, address = ""): boolean {
  return /(?:\botp\b|one[ -]?time|verification|authentication|security code|\bpassword\b|passcode|\bpin\b|\b2fa\b|log[ -]?in|sign[ -]?in|bank|wallet|reset|ভেরিফিকেশন|যাচাই|পাসওয়ার্ড|ওটিপি|গোপন|পিন|[?&](?:token|secret|password|otp|code)=|\bBearer\s|\beyJ[a-zA-Z\d_-]{15})/i.test(body) || /bank|wallet|auth|otp|verify/i.test(address);
}
export function searchWords(value: string): string[] {
  const normalized=value.normalize("NFKC").toLowerCase();
  if(/^\+?[\d ()-]{7,}$/.test(normalized.trim()))return [normalized.replace(/\D/g,"")];
  const phoneTokens=(normalized.match(/\+?\d[\d ()-]{5,}\d/g)??[]).map(x=>x.replace(/\D/g,""));
  return [...new Set([...(normalized.match(/[\p{L}\p{M}\p{N}]+/gu) ?? []),...phoneTokens].filter(x=>x.length<=80))].slice(0,256);
}
export function communicationSearchTerms(value: string): string[] { return searchWords(value).map(word=>communicationDigest("search",word)); }
