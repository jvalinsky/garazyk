import * as cbor from "@ipld/dag-cbor";

export class FirehoseEvent {
  constructor(
    public seq: number,
    public type: string,
    public payload: any | Uint8Array
  ) {}
}

export class FirehoseClient {
  public wsUrl: string;
  public events: FirehoseEvent[] = [];

  constructor(relayUrl = "ws://localhost:2584") {
    this.wsUrl = relayUrl.replace("http://", "ws://").replace("https://", "wss://").replace(/\/$/, "");
  }

  subscribe(
    callback?: (e: FirehoseEvent) => void,
    durationS = 10.0,
    cursor?: number,
    signal?: AbortSignal,
  ): Promise<void> {
    const url = new URL(`${this.wsUrl}/xrpc/com.atproto.sync.subscribeRepos`);
    if (cursor !== undefined) {
      url.searchParams.append("cursor", cursor.toString());
    }

    return new Promise((resolve) => {
      if (signal?.aborted) {
        resolve();
        return;
      }

      console.log(`Connecting to firehose: ${url.toString()}`);
      const ws = new WebSocket(url.toString());
      ws.binaryType = "arraybuffer";

      const timeout = setTimeout(() => {
        ws.close();
        resolve();
      }, durationS * 1000);

      const onAbort = () => {
        clearTimeout(timeout);
        ws.close();
        resolve();
      };
      signal?.addEventListener("abort", onAbort, { once: true });

      ws.onopen = () => {
        console.log("Firehose connected");
      };

      ws.onmessage = (event) => {
        try {
          if (event.data instanceof ArrayBuffer) {
            const buf = new Uint8Array(event.data);
            let seq = 0;
            let type = "unknown";

            try {
              const [header, _] = cbor.decode(buf) as any;
              seq = header.seq || 0;
              type = header.t || header.op || "unknown";
            } catch {
              // ignore partial parse failures
            }

            const fe = new FirehoseEvent(seq, type, buf);
            if (callback) callback(fe);
          }
        } catch (e) {
          console.warn("Firehose parse error", e);
        }
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        signal?.removeEventListener("abort", onAbort);
        ws.close();
        resolve();
      };

      ws.onclose = () => {
        clearTimeout(timeout);
        signal?.removeEventListener("abort", onAbort);
        resolve();
      };
    });
  }

  collect(durationS = 5.0, cursor?: number, signal?: AbortSignal): Promise<FirehoseEvent[]> {
    this.events = [];
    return this.subscribe((e) => this.events.push(e), durationS, cursor, signal)
      .then(() => this.events);
  }
}
