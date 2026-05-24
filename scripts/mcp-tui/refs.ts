export class RefManager {
  private nextRef = 1;
  private byKey = new Map<string, string>();

  ref(key: string): string {
    const existing = this.byKey.get(key);
    if (existing) return existing;
    const r = `e${this.nextRef++}`;
    this.byKey.set(key, r);
    return r;
  }

  panelRef(panelId: string): string {
    const existing = this.byKey.get(`panel:${panelId}`);
    if (existing) return existing;
    const r = `p${this.byKey.size + 1}`;
    this.byKey.set(`panel:${panelId}`, r);
    return r;
  }

  reset(): void {
    this.nextRef = 1;
    this.byKey.clear();
  }
}
