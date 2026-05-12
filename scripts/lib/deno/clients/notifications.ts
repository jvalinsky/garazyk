import { TransportLayer } from "../transport.ts";

export class NotificationsClient {
  constructor(private transport: TransportLayer) {}

  async listNotifications(token: string, limit = 50) {
    return await this.transport.get("app.bsky.notification.listNotifications", { limit }, token);
  }

  async updateSeen(token: string, limit = 0) {
    return await this.transport.post("app.bsky.notification.updateSeen", { limit }, token);
  }

  async registerPush(
    serviceDid: string,
    token: string,
    platform: string,
    appId: string,
    authToken: string
  ) {
    return await this.transport.post(
      "app.bsky.notification.registerPush",
      { serviceDid, token, platform, appId },
      authToken
    );
  }

  async unregisterPush(
    serviceDid: string,
    token: string,
    platform: string,
    appId: string,
    authToken: string
  ) {
    return await this.transport.post(
      "app.bsky.notification.unregisterPush",
      { serviceDid, token, platform, appId },
      authToken
    );
  }

  async getNotificationPreferences(token: string) {
    return await this.transport.get("app.bsky.notification.getPreferences", undefined, token);
  }

  async putNotificationPreferences(preferences: Record<string, any>, token: string) {
    return await this.transport.post(
      "app.bsky.notification.putPreferences",
      { priority: preferences.priority ?? false },
      token
    );
  }

  async listActivitySubscriptions(token: string, limit = 50) {
    return await this.transport.get(
      "app.bsky.notification.listActivitySubscriptions",
      { limit },
      token
    );
  }

  async putActivitySubscription(
    subject: string,
    postEnabled: boolean,
    replyEnabled: boolean,
    token: string
  ) {
    return await this.transport.post(
      "app.bsky.notification.putActivitySubscription",
      { subject, postEnabled, replyEnabled },
      token
    );
  }
}
