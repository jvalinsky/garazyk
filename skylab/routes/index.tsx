// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract SkyLab SPA shell
 * @discussion Serves the single-page Bluesky client HTML. Injects
 * service configuration as an inline script for instant boot (no
 * separate /skylab/api/config fetch needed on first load).
 */

import { Head } from "$fresh/runtime.ts";
import { Handlers, PageProps } from "$fresh/server.ts";
import {
  APPVIEW_READ_METHODS,
  METHOD_ROUTES,
  SERVICE_URLS,
  VIDEO_SERVICE_DID,
} from "../services/config.ts";

interface PageData {
  services: Record<string, string>;
  methodRoutes: Record<string, string>;
  appviewReadMethods: string[];
  videoServiceDid: string;
}

export const handler: Handlers<PageData> = {
  GET(_req, ctx) {
    return ctx.render({
      services: SERVICE_URLS,
      methodRoutes: METHOD_ROUTES,
      appviewReadMethods: [...APPVIEW_READ_METHODS],
      videoServiceDid: VIDEO_SERVICE_DID,
    });
  },
};

export default function SkyLabPage({ data }: PageProps<PageData>) {
  const { services, methodRoutes, appviewReadMethods, videoServiceDid } = data;

  return (
    <>
      <Head>
        <title>SkyLab — Bluesky Client</title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="stylesheet" href="/skylab/css/skylab.css" />
        <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.7/dist/hls.min.js" />
      </Head>
      <body>
        <div id="skylab-app" class="skylab-app">
          {/* Sidebar */}
          <nav class="skylab-sidebar">
            <div class="skylab-brand">
              <span class="skylab-brand-icon">&#9672;</span>
              <span class="skylab-brand-text">SkyLab</span>
            </div>

            <div class="skylab-nav">
              <button class="skylab-nav-item active" data-panel="timeline">
                <span class="skylab-nav-icon">&#9776;</span>
                <span class="skylab-nav-label">Timeline</span>
              </button>
              <button class="skylab-nav-item" data-panel="chat">
                <span class="skylab-nav-icon">&#9993;</span>
                <span class="skylab-nav-label">Chat</span>
              </button>
              <button class="skylab-nav-item" data-panel="video">
                <span class="skylab-nav-icon">&#9654;</span>
                <span class="skylab-nav-label">Video</span>
              </button>
              <button class="skylab-nav-item" data-panel="firehose">
                <span class="skylab-nav-icon">&#9889;</span>
                <span class="skylab-nav-label">Firehose</span>
              </button>
              <button class="skylab-nav-item" data-panel="admin">
                <span class="skylab-nav-icon">&#9881;</span>
                <span class="skylab-nav-label">Admin</span>
              </button>
            </div>

            {/* Auth status */}
            <div class="skylab-auth-status" id="auth-status">
              <div class="skylab-auth-logged-out" id="auth-logged-out">
                <button class="skylab-btn skylab-btn-primary" id="login-btn">Sign In</button>
              </div>
              <div class="skylab-auth-logged-in" id="auth-logged-in" style="display:none;">
                <div class="skylab-auth-handle" id="auth-handle">—</div>
                <div class="skylab-auth-did" id="auth-did">—</div>
                <button class="skylab-btn skylab-btn-sm" id="logout-btn">Sign Out</button>
              </div>
            </div>
          </nav>

          {/* Main content */}
          <main class="skylab-main">
            {/* Login overlay */}
            <div class="skylab-login-overlay" id="login-overlay" style="display:none;">
              <div class="skylab-card">
                <h2 class="skylab-card-title">Sign In to SkyLab</h2>
                <div class="skylab-form-group">
                  <label class="skylab-form-label">Handle or Email</label>
                  <input
                    type="text"
                    class="skylab-form-input"
                    id="login-identifier"
                    placeholder="luna.test"
                    autocomplete="username"
                  />
                </div>
                <div class="skylab-form-group">
                  <label class="skylab-form-label">Password</label>
                  <input
                    type="password"
                    class="skylab-form-input"
                    id="login-password"
                    placeholder="password"
                    autocomplete="current-password"
                  />
                </div>
                <div class="skylab-form-error" id="login-error" style="display:none;"></div>
                <button class="skylab-btn skylab-btn-primary skylab-btn-block" id="login-submit">
                  Sign In
                </button>
                <button class="skylab-btn skylab-btn-block" id="login-cancel">Cancel</button>
              </div>
            </div>

            {/* Panel: Timeline */}
            <div class="skylab-panel active" id="panel-timeline">
              <div class="skylab-panel-header">
                <h1 class="skylab-panel-title">Timeline</h1>
                <button class="skylab-btn skylab-btn-sm" id="timeline-refresh">Refresh</button>
              </div>
              <div class="skylab-composer" id="timeline-composer">
                <textarea
                  class="skylab-composer-input"
                  id="composer-text"
                  placeholder="What's up?"
                  rows={3}
                  maxlength={300}
                >
                </textarea>
                <div class="skylab-composer-video" id="composer-video">
                  <input
                    type="file"
                    class="skylab-form-input"
                    id="composer-video-file"
                    accept="video/mp4,video/quicktime,video/x-matroska"
                  />
                  <input
                    type="text"
                    class="skylab-form-input"
                    id="composer-video-alt"
                    placeholder="Alt text for video"
                    maxlength={1000}
                  />
                  <div
                    class="skylab-video-progress"
                    id="composer-video-progress"
                    style="display:none;"
                  >
                    <div class="skylab-progress-bar">
                      <div
                        class="skylab-progress-fill"
                        id="composer-video-progress-fill"
                        style="width:0%"
                      >
                      </div>
                    </div>
                    <span class="skylab-progress-text" id="composer-video-progress-text">
                      No video attached
                    </span>
                  </div>
                </div>
                <div class="skylab-composer-actions">
                  <span class="skylab-char-count" id="composer-char-count">0/300</span>
                  <button class="skylab-btn skylab-btn-primary skylab-btn-sm" id="composer-post">
                    Post
                  </button>
                </div>
              </div>
              <div class="skylab-feed" id="timeline-feed">
                <div class="skylab-empty-state">Sign in to see your timeline</div>
              </div>
            </div>

            {/* Panel: Chat */}
            <div class="skylab-panel" id="panel-chat">
              <div class="skylab-panel-header">
                <h1 class="skylab-panel-title">Chat</h1>
                {/* E2EE (Germ) mode selector removed per the Phase 10 product-surface
                    decision (docs/plans/phase-10-product-surface-decision-brief.md):
                    selecting it announced client-side encryption but silently sent
                    plaintext, a privacy/consent failure. */}
              </div>
              <div class="skylab-chat-layout">
                <div class="skylab-chat-list" id="chat-list">
                  <div class="skylab-empty-state">No conversations</div>
                </div>
                <div class="skylab-chat-view" id="chat-view">
                  <div class="skylab-empty-state">Select a conversation</div>
                </div>
              </div>
            </div>

            {/* Panel: Video */}
            <div class="skylab-panel" id="panel-video">
              <div class="skylab-panel-header">
                <h1 class="skylab-panel-title">Video</h1>
              </div>
              <div class="skylab-video-upload" id="video-upload">
                <div class="skylab-card">
                  <h3 class="skylab-card-title">Upload Video</h3>
                  <input
                    type="file"
                    class="skylab-form-input"
                    id="video-file-input"
                    accept="video/mp4,video/quicktime,video/x-matroska"
                  />
                  <div class="skylab-video-progress" id="video-progress" style="display:none;">
                    <div class="skylab-progress-bar">
                      <div class="skylab-progress-fill" id="video-progress-fill" style="width:0%">
                      </div>
                    </div>
                    <span class="skylab-progress-text" id="video-progress-text">0%</span>
                  </div>
                  <button class="skylab-btn skylab-btn-primary" id="video-upload-btn">
                    Upload
                  </button>
                </div>
              </div>
              <div class="skylab-video-jobs" id="video-jobs">
                <div class="skylab-empty-state">No video jobs</div>
              </div>
            </div>

            {/* Panel: Firehose */}
            <div class="skylab-panel" id="panel-firehose">
              <div class="skylab-panel-header">
                <h1 class="skylab-panel-title">Firehose</h1>
                <div class="skylab-firehose-controls">
                  <button class="skylab-btn skylab-btn-sm skylab-btn-primary" id="firehose-connect">
                    Connect
                  </button>
                  <button
                    class="skylab-btn skylab-btn-sm"
                    id="firehose-disconnect"
                    style="display:none;"
                  >
                    Disconnect
                  </button>
                  <span class="skylab-firehose-seq" id="firehose-seq">seq: 0</span>
                </div>
              </div>
              <div class="skylab-firehose-filter">
                <input
                  type="text"
                  class="skylab-form-input"
                  id="firehose-filter"
                  placeholder="Filter by NSID or DID..."
                />
              </div>
              <div class="skylab-firehose-events" id="firehose-events">
                <div class="skylab-empty-state">Not connected</div>
              </div>
            </div>

            {/* Panel: Admin */}
            <div class="skylab-panel" id="panel-admin">
              <div class="skylab-panel-header">
                <h1 class="skylab-panel-title">Admin</h1>
              </div>
              <div class="skylab-admin-services" id="admin-services">
                <div class="skylab-empty-state">Loading service status...</div>
              </div>
            </div>
          </main>
        </div>

        {/* Service config as JSON script tag — read by boot.js */}
        <script
          type="application/json"
          id="skylab-config"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({ services, methodRoutes, appviewReadMethods, videoServiceDid }),
          }}
        />
        <script src="/skylab/js/skylab-bridge.js" />
        <script src="/skylab/js/skylab-timeline.js" />
        <script src="/skylab/js/skylab-chat.js" />
        <script src="/skylab/js/skylab-video.js" />
        <script src="/skylab/js/skylab-admin.js" />
        <script src="/skylab/js/skylab-firehose.js" />
        <script src="/skylab/js/skylab-boot.js" />
      </body>
    </>
  );
}
