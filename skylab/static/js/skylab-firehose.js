// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab Firehose Panel — Live event stream with filtering and rate tracking.
 */

function initFirehosePanel(bridge) {
  const connectBtn = document.getElementById("firehose-connect");
  const disconnectBtn = document.getElementById("firehose-disconnect");
  const seqEl = document.getElementById("firehose-seq");
  const filterInput = document.getElementById("firehose-filter");
  const eventsEl = document.getElementById("firehose-events");

  let events = [];
  let filterText = "";
  let rateCounter = 0;
  let rateDisplay = 0;
  const MAX_EVENTS = 500;

  // ---- Rate tracking ----
  setInterval(() => {
    rateDisplay = rateCounter;
    rateCounter = 0;
  }, 1000);

  // ---- Connect/Disconnect ----
  connectBtn.addEventListener("click", () => {
    bridge.subscribeFirehose();
    connectBtn.style.display = "none";
    disconnectBtn.style.display = "inline-flex";
    eventsEl.innerHTML = "";
    events = [];
  });

  disconnectBtn.addEventListener("click", () => {
    bridge.unsubscribeFirehose();
    connectBtn.style.display = "inline-flex";
    disconnectBtn.style.display = "none";
  });

  // ---- Firehose events ----
  bridge.on("firehose_frame", (frame) => {
    rateCounter++;
    seqEl.textContent = `seq: ${frame.seq} | ${rateDisplay} evt/s`;

    const event = {
      seq: frame.seq,
      type: frame.type || "unknown",
      size: frame.size || 0,
      time: new Date().toISOString().substring(11, 23),
    };

    // Try to extract type/DID from binary frame
    if (frame.raw instanceof ArrayBuffer) {
      // Binary frame — we can't easily parse CBOR in browser
      // without a library, so just show metadata
      event.type = "binary";
      event.size = frame.raw.byteLength;
    } else if (typeof frame.data === "string") {
      try {
        const parsed = JSON.parse(frame.data);
        event.type = parsed.type || "text";
        event.did = parsed.did || "";
      } catch (e) {
        event.type = "text";
      }
    }

    events.unshift(event);
    if (events.length > MAX_EVENTS) events.pop();

    renderFilteredEvents();
  });

  bridge.on("firehose_open", () => {
    eventsEl.innerHTML =
      '<div class="skylab-empty-state" style="color:var(--color-success);">Connected to firehose</div>';
  });

  bridge.on("firehose_close", () => {
    connectBtn.style.display = "inline-flex";
    disconnectBtn.style.display = "none";
  });

  bridge.on("firehose_error", () => {
    eventsEl.innerHTML =
      '<div class="skylab-empty-state" style="color:var(--color-destructive);">Connection error</div>';
  });

  // ---- Filter ----
  filterInput.addEventListener("input", () => {
    filterText = filterInput.value.trim().toLowerCase();
    renderFilteredEvents();
  });

  function renderFilteredEvents() {
    const filtered = filterText
      ? events.filter((e) =>
        (e.type || "").toLowerCase().includes(filterText) ||
        (e.did || "").toLowerCase().includes(filterText)
      )
      : events;

    // Only render visible events (max 100 at a time for performance)
    const visible = filtered.slice(0, 100);
    eventsEl.innerHTML = "";

    for (const event of visible) {
      const el = document.createElement("div");
      el.className = "skylab-firehose-event";
      el.innerHTML = `
                <span class="skylab-firehose-event-seq">${event.seq}</span>
                <span class="skylab-firehose-event-type">${escapeHtml(event.type)}</span>
                <span class="skylab-firehose-event-did">${escapeHtml(event.did || "")}</span>
                <span style="margin-left:auto;color:var(--color-text-tertiary);">${event.time}</span>
            `;
      eventsEl.appendChild(el);
    }

    if (filtered.length > 100) {
      const more = document.createElement("div");
      more.className = "skylab-empty-state";
      more.textContent = `+${filtered.length - 100} more events`;
      eventsEl.appendChild(more);
    }
  }

  // ---- HTML escaping ----
  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str || "";
    return div.innerHTML;
  }
}
