import { domainToASCII } from "node:url";

export type WebsiteRuleType = "DOMAIN" | "URL" | "KEYWORD" | "CATEGORY";
const categories = new Set(["ADULT", "PORNOGRAPHY", "GAMBLING", "BETTING", "GAMING", "SOCIAL", "VIOLENCE", "SAFESEARCH"]);
export function normalizeWebsiteTarget(ruleType: WebsiteRuleType, input: string): { ruleType: WebsiteRuleType; target: string } {
  const value = input.trim();
  if (!value || value.length > 2048 || [...value].some(c => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127 || c === "\\")) throw new Error("Enter a valid website address");
  if (ruleType === "KEYWORD") {
    const target = value.replace(/^\*|\*$/g, "").trim().toLowerCase();
    if (!target || target.length > 255) throw new Error("Enter a keyword of 1–255 characters");
    return { ruleType, target };
  }
  if (ruleType === "CATEGORY") {
    const target = value.toUpperCase();
    if (!categories.has(target)) throw new Error("Unsupported website category");
    return { ruleType, target };
  }
  const wildcard = value.startsWith("*.");
  if (wildcard && ruleType === "URL") throw new Error("Wildcards require domain scope");
  const candidate = wildcard ? value.slice(2) : value;
  if (/\s|\*/.test(candidate) || (candidate.includes(":") && !/^https?:\/\//i.test(candidate))) throw new Error("Use an HTTP/HTTPS website address");
  const url = new URL(/^https?:\/\//i.test(candidate) ? candidate : `https://${candidate}`);
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error("Use an HTTP/HTTPS address without credentials");
  // Reject IDNA deviation characters rather than disagreeing with Android's IDNA2003 parser.
  if (/[ßς\u200c\u200d]/i.test(candidate.replace(/^https?:\/\//i, "").split(/[/?#]/)[0])) throw new Error("Enter the ASCII punycode form of this international domain");
  const hostname = domainToASCII(url.hostname).toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
  if (!hostname || hostname.length > 253 || (hostname.split(".").length < 2 && !(wildcard && /^[a-z]{2,63}$/.test(hostname))) || !hostname.split(".").every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) throw new Error("Enter a valid hostname, for example example.com");
  url.hostname = hostname;
  url.hash = "";
  if (ruleType === "DOMAIN" && (url.pathname !== "/" || url.search || url.port)) {
    if (wildcard) throw new Error("Wildcard domain rules cannot contain paths or ports");
    ruleType = "URL"; // Never broaden a path-specific input into a hostname-wide rule.
  }
  const target = ruleType === "DOMAIN" ? `${wildcard ? "*." : ""}${hostname}` : url.toString().replace(/%[a-f\d]{2}/gi, v => v.toUpperCase());
  if (target.length > 2048) throw new Error("The normalized website address is too long");
  return { ruleType, target };
}
