/** Notification and push subscription management @module notifications */
import { TransportLayer } from "../transport.ts";

/** Client for notification and push-preference XRPC methods. */
export class NotificationsClient {
  /**
   * Constructs the notifications client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * List notifications for the authenticated user
   * @param token - The authentication bearer token
   * @param limit - Max notifications to return
   * @returns A promise that resolves to the notifications list
   * @throws XrpcError if the request fails
   */
  async listNotifications(token: string, limit = 50): Promise<any> {
    return await this.transport.get("app.bsky.notification.listNotifications", { limit }, token);
  }

  /**
   * Mark notifications as seen
   * @param token - The authentication bearer token
   * @param limit - Limit for update
   * @returns A promise that resolves to the update seen response
   * @throws XrpcError if the request fails
   */
  async updateSeen(token: string, limit = 0): Promise<any> {
    return await this.transport.post("app.bsky.notification.updateSeen", { limit }, token);
  }

  /**
   * Register a push notification endpoint
   * @param serviceDid - The service DID
   * @param token - The push token
   * @param platform - The device platform
   * @param appId - The app ID
   * @param authToken - The authentication bearer token
   * @returns A promise that resolves to the register push response
   * @throws XrpcError if the request fails
   */
  async registerPush(
    serviceDid: string,
    token: string,
    platform: string,
    appId: string,
    authToken: string
  ): Promise<any> {
    return await this.transport.post(
      "app.bsky.notification.registerPush",
      { serviceDid, token, platform, appId },
      authToken
    );
  }

  /**
   * Unregister a push notification endpoint
   * @param serviceDid - The service DID
   * @param token - The push token
   * @param platform - The device platform
   * @param appId - The app ID
   * @param authToken - The authentication bearer token
   * @returns A promise that resolves to the unregister push response
   * @throws XrpcError if the request fails
   */
  async unregisterPush(
    serviceDid: string,
    token: string,
    platform: string,
    appId: string,
    authToken: string
  ): Promise<any> {
    return await this.transport.post(
      "app.bsky.notification.unregisterPush",
      { serviceDid, token, platform, appId },
      authToken
    );
  }

  /**
   * Get notification preferences
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the notification preferences
   * @throws XrpcError if the request fails
   */
  async getNotificationPreferences(token: string): Promise<any> {
    return await this.transport.get("app.bsky.notification.getPreferences", undefined, token);
  }

  /**
   * Set notification preferences
   * @param preferences - The notification preferences
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the set preferences response
   * @throws XrpcError if the request fails
   */
  async putNotificationPreferences(preferences: Record<string, any>, token: string): Promise<any> {
    return await this.transport.post(
      "app.bsky.notification.putPreferences",
      { priority: preferences.priority ?? false },
      token
    );
  }

  /**
   * List activity subscriptions
   * @param token - The authentication bearer token
   * @param limit - Max subscriptions to return
   * @returns A promise that resolves to the activity subscriptions
   * @throws XrpcError if the request fails
   */
  async listActivitySubscriptions(token: string, limit = 50): Promise<any> {
    return await this.transport.get(
      "app.bsky.notification.listActivitySubscriptions",
      { limit },
      token
    );
  }

  /**
   * Set activity subscription preferences for a subject
   * @param subject - The subject DID or reference
   * @param postEnabled - Whether post notifications are enabled
   * @param replyEnabled - Whether reply notifications are enabled
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the set subscription response
   * @throws XrpcError if the request fails
   */
  async putActivitySubscription(
    subject: string,
    postEnabled: boolean,
    replyEnabled: boolean,
    token: string
  ): Promise<any> {
    return await this.transport.post(
      "app.bsky.notification.putActivitySubscription",
      { subject, postEnabled, replyEnabled },
      token
    );
  }
}
