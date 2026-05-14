import { TransportLayer, XrpcError } from "../transport.ts";

export class AdminClient {
  constructor(private transport: TransportLayer) {}

  async getSubjectStatus(did: string, token: string) {
    return await this.transport.get("com.atproto.admin.getSubjectStatus", { did }, token);
  }

  async updateSubjectStatus(
    subject: Record<string, any>,
    options: { takedown?: Record<string, any>; token?: string } = {}
  ) {
    const body: Record<string, any> = { subject };
    if (options.takedown) body.takedown = options.takedown;
    return await this.transport.post("com.atproto.admin.updateSubjectStatus", body, options.token);
  }

  async createReport(
    reasonType: string,
    subject: Record<string, any>,
    reason: string,
    token: string
  ) {
    return await this.transport.post(
      "com.atproto.moderation.createReport",
      { reasonType, subject, reason },
      token
    );
  }

  async getLabels(uris: string[], token?: string) {
    // Porting the special repeated-param logic from Python transport.py
    const params: Record<string, any> = { "uris[]": uris };
    return await this.transport.get("com.atproto.label.getLabels", params, token);
  }

  async login(password: string): Promise<string> {
    const url = `${this.transport.baseUrl}/admin/login`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });

    if (!res.ok) {
      throw new XrpcError("/admin/login", res.status, await res.text());
    }

    const data = await res.json();
    const token = data.token || data.ui_admin_token;
    if (!token) {
      throw new XrpcError("/admin/login", 200, { error: "missing token in response" });
    }
    return token;
  }
}
