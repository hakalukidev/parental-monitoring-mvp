export function dateInZone(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date);
  const part = (name: string) => parts.find((p) => p.type === name)!.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}
/** Calendar boundaries by date in the named zone, including 23/25-hour DST days. */
export function localDayBounds(timeZone: string, date = new Date()): { start: Date; end: Date } {
  const day = dateInZone(date, timeZone);
  const center = Math.floor(date.getTime() / 1000);
  const boundary = (after: boolean) => {
    let low = center - 48 * 3600, high = center + 48 * 3600;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      const candidate = dateInZone(new Date(mid * 1000), timeZone);
      if (after ? candidate > day : candidate >= day) high = mid; else low = mid + 1;
    }
    return new Date(low * 1000);
  };
  return { start: boundary(false), end: boundary(true) };
}
