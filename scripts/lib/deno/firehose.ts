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

  async collect(durationS = 5.0, cursor?: number): Promise<FirehoseEvent[]> {
    this.events = [];
    await this.subscribe((e) => this.events.push(e), durationS, cursor);
    return this.events;
  }

  async subscribe(
    callback?: (e: FirehoseEvent) => void,
    durationS = 10.0,
    cursor?: number
  ): Promise<void> {
    const url = new URL(`${this.wsUrl}/xrpc/com.atproto.sync.subscribeRepos`);
    if (cursor !== undefined) {
      url.searchParams.append("cursor", cursor.toString());
    }

    return new Promise((resolve, reject) => {
      console.log(`Connecting to firehose: ${url.toString()}`);
      const ws = new WebSocket(url.toString());
      ws.binaryType = "arraybuffer";

      const timeout = setTimeout(() => {
        ws.close();
        resolve();
      }, durationS * 1000);

      ws.onopen = () => {
        console.log("Firehose connected");
      };

      ws.onmessage = (event) => {
        try {
          if (event.data instanceof ArrayBuffer) {
            const buf = new Uint8Array(event.data);
            // In ATProto firehose, messages are typically two concatenated DAG-CBOR blocks: header + body
            // We use standard CBOR decoding (or just pass the raw bytes for tests that assert traffic)
            // For now, we wrap the raw buffer, and decode the header to get seq/op.
            // Simplified parsing for scenario requirements:
            let seq = 0;
            let type = "unknown";
            
            try {
              // Attempt to decode first CBOR block (header)
              const [header, _] = cbor.decode(buf) as any;
              seq = header.seq || 0;
              type = header.t || header.op || "unknown";
            } catch (e) {
              // Ignore partial parse failures
            }
            
            const fe = new FirehoseEvent(seq, type, buf);
            if (callback) callback(fe);
          }
        } catch (e) {
          console.warn("Firehose parse error", e);
        }
      };

      ws.onerror = (error) => {
        clearTimeout(timeout);
        ws.close();
        reject(new Error("WebSocket error"));
      };

      ws.onclose = () => {
        clearTimeout(timeout);
        resolve();
      };
    });
  }
}
