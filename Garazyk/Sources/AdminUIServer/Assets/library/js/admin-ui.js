// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

const csrfNonceMeta = () => document.querySelector('meta[name="csrf-nonce"]');
const byID = (id) => document.getElementById(id);
const videoJobsContentTarget = () => (byID('video-jobs-content') ? '#video-jobs-content' : '#video-jobs');

function refreshCSRFNonce(response) {
  const nextNonce = response.headers.get('X-UI-Admin-Nonce');
  const meta = csrfNonceMeta();
  if (nextNonce && meta) {
    meta.content = nextNonce;
  }
}

async function adminRequest(path, payload = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const nonce = csrfNonceMeta()?.content;
  if (nonce) {
    headers['X-UI-Admin-Nonce'] = nonce;
  }

  const response = await fetch(path, {
    method: 'POST',
    credentials: 'same-origin',
    headers,
    body: JSON.stringify(payload),
  });
  refreshCSRFNonce(response);
  return response;
}

// Admin endpoints only return authenticated, server-rendered UI fragments. Keep
// untrusted values out of this helper; server data is escaped before rendering.
async function replaceServerHTML(target, response) {
  if (!target) return;
  target.innerHTML = await response.text();
}

function showError(target, message) {
  if (!target) return;
  target.replaceChildren();
  const alert = document.createElement('div');
  alert.className = 'alert alert-destructive';
  alert.textContent = message;
  target.append(alert);
}

function reloadPartial(path, targetSelector) {
  const target = document.querySelector(targetSelector);
  if (!target) return;
  if (window.htmx) {
    window.htmx.ajax('GET', path, { target, swap: 'innerHTML' });
    return;
  }
  fetch(path, { credentials: 'same-origin' })
    .then((response) => replaceServerHTML(target, response))
    .catch(() => showError(target, 'Unable to refresh data.'));
}

function loadLazyPartials(root) {
  if (!root || !root.querySelectorAll) return;
  root.querySelectorAll('[hx-get]').forEach((el) => {
    // Forms fetch on submit only.
    if (el.tagName === 'FORM') return;
    if (el.dataset.uiLoaded === '1') return;
    const path = el.getAttribute('hx-get');
    if (!path) return;
    // Already hydrated (e.g. MST shell with DID input) — never clobber.
    if (el.innerHTML.trim()) {
      el.dataset.uiLoaded = '1';
      return;
    }
    // Mark before the request so overlapping revealed/load handlers cannot
    // stampede the same placeholder.
    el.dataset.uiLoaded = '1';
    if (window.htmx) {
      window.htmx.ajax('GET', path, { source: el, target: el, swap: 'innerHTML' });
      return;
    }
    fetch(path, { credentials: 'same-origin' })
      .then((response) => replaceServerHTML(el, response))
      .catch(() => {
        el.dataset.uiLoaded = '0';
        showError(el, 'Unable to load data.');
      });
  });
}

const pollTimers = new Map();

function stopPartialPolls() {
  pollTimers.forEach((id) => clearInterval(id));
  pollTimers.clear();
}

function startPartialPolls(pane) {
  stopPartialPolls();
  if (!pane) return;
  pane.querySelectorAll('[data-ui-poll-seconds]').forEach((el) => {
    const seconds = Number(el.dataset.uiPollSeconds);
    const path = el.getAttribute('hx-get');
    if (!seconds || seconds < 1 || !path || !el.id) return;
    const timer = setInterval(() => {
      if (pane.hidden) return;
      if (window.htmx) {
        window.htmx.ajax('GET', path, { source: el, target: el, swap: 'innerHTML' });
      }
    }, seconds * 1000);
    pollTimers.set(el.id, timer);
  });
}

function switchTab(name, options = {}) {
  document.querySelectorAll('.tab-pane').forEach((pane) => {
    pane.hidden = pane.id !== `tab-${name}`;
  });
  document.querySelectorAll('.ui-tab').forEach((segment) => {
    const selected = segment.dataset.tab === name;
    segment.classList.toggle('active', selected);
    segment.setAttribute('aria-selected', String(selected));
    // Roving tabindex: only the selected tab is in the Tab order; arrow
    // keys move among the rest (WAI-ARIA APG tabs pattern).
    segment.tabIndex = selected ? 0 : -1;
  });
  if (options.focus) {
    byID(`tabbtn-${name}`)?.focus();
  }

  const pane = byID(`tab-${name}`);
  if (!pane) return;
  // One-shot lazy load for the active pane only. Do not use hx-trigger
  // "revealed" — empty .admin-partial boxes re-intersect forever and spam.
  loadLazyPartials(pane);
  hydrateUIWidgets(pane);
  startPartialPolls(pane);
}

// Arrow-key navigation between tabs, per the WAI-ARIA APG tabs pattern.
document.getElementById('nav-tabs')?.addEventListener('keydown', (event) => {
  const tabs = Array.from(document.querySelectorAll('.ui-tab'));
  const currentIndex = tabs.indexOf(event.target.closest('.ui-tab'));
  if (currentIndex === -1) return;

  let nextIndex = null;
  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
    nextIndex = (currentIndex + 1) % tabs.length;
  } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
    nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
  } else if (event.key === 'Home') {
    nextIndex = 0;
  } else if (event.key === 'End') {
    nextIndex = tabs.length - 1;
  } else {
    return;
  }

  event.preventDefault();
  switchTab(tabs[nextIndex].dataset.tab, { focus: true });
});

function activeTabPane() {
  return Array.from(document.querySelectorAll('.tab-pane')).find((pane) => !pane.hidden) || document;
}

function didFromText(text) {
  const match = (text || '').match(/\bdid:[a-z0-9]+:[A-Za-z0-9._:-]+/);
  return match ? match[0] : '';
}

function inputExpectsDID(element) {
  if (!element || element.disabled || element.readOnly) return false;
  if (element.tagName === 'INPUT') {
    const type = (element.type || 'text').toLowerCase();
    if (['hidden', 'checkbox', 'radio', 'button', 'submit', 'reset', 'password'].includes(type)) return false;
  } else if (element.tagName !== 'TEXTAREA') {
    return false;
  }
  const groupLabel = element.closest('.form-group')?.querySelector('label')?.textContent || '';
  const hint = [element.id, element.name, element.placeholder, element.getAttribute('aria-label'), groupLabel]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  return hint.includes('did');
}

function fillVisibleDIDInputs(did) {
  if (!did) return;
  activeTabPane().querySelectorAll('input,textarea').forEach((element) => {
    if (inputExpectsDID(element)) {
      element.value = did;
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
    }
  });
}

async function postHTML(path, payload, target, refreshPath, refreshTarget) {
  const response = await adminRequest(path, payload);
  await replaceServerHTML(target, response);
  if (refreshPath && refreshTarget) reloadPartial(refreshPath, refreshTarget);
}

async function saveConnections() {
  const services = [['pds', 'pds'], ['plc', 'plc'], ['relay', 'relay'], ['appview', 'appView'], ['chat', 'chat'], ['video', 'video']];
  const body = {};
  for (const [id, key] of services) {
    const url = byID(`conn-${id}-url`);
    const token = byID(`conn-${id}-token`);
    if (!url || !token) continue;
    body[`${key}URL`] = url.value;
    body[`${key}Token`] = token.value || token.dataset.originalToken || '';
  }
  await postHTML('/admin/actions/update-connections', body, byID('connections-form'));
}

async function testConnection(service) {
  const url = byID(`conn-${service}-url`);
  const token = byID(`conn-${service}-token`);
  const target = byID(`conn-${service}-test-result`);
  if (!url || !token || !target) return;
  target.textContent = 'Testing…';
  try {
    const response = await adminRequest('/admin/actions/test-connection', {
      service,
      url: url.value,
      token: token.value || token.dataset.originalToken || '',
    });
    const result = await response.json();
    target.textContent = result.status === 'online' ? 'Connected' : (result.error || result.status || 'Failed');
    target.className = `text-sm ${result.status === 'online' ? 'text-success' : 'text-destructive'}`;
  } catch (_) {
    target.textContent = 'Failed';
    target.className = 'text-sm text-destructive';
  }
}

function shortCID(cid) {
  if (!cid || typeof cid !== 'string') return '';
  return cid.length > 10 ? `${cid.slice(0, 6)}…${cid.slice(-4)}` : cid;
}

function buildMSTHierarchy(flat) {
  if (!flat?.nodes?.length || !flat.rootCID) return null;
  const nodeMap = new Map();
  flat.nodes.forEach((node) => {
    if (node?.cid) nodeMap.set(node.cid, node);
  });
  const build = (cid) => {
    const node = nodeMap.get(cid);
    if (!node) return null;
    const clone = { cid: node.cid, kind: node.kind, level: node.level, entries: node.entries || [] };
    const children = [];
    if (node.left) {
      const left = build(node.left);
      if (left) {
        left.edgeLabel = 'L';
        children.push(left);
      }
    }
    (node.entries || []).forEach((entry) => {
      if (entry?.tree) {
        const child = build(entry.tree);
        if (child) {
          child.edgeLabel = entry.fullKey || entry.key || '';
          children.push(child);
        }
        return;
      }
      // Record leaves (value CID, no subtree) still deserve a visual node.
      if (entry?.value || entry?.fullKey || entry?.key) {
        children.push({
          cid: entry.value || entry.fullKey || entry.key,
          kind: 'leaf',
          level: (node.level || 0) + 1,
          edgeLabel: entry.fullKey || entry.key || 'record',
          entries: [],
        });
      }
    });
    if (children.length) clone.children = children;
    return clone;
  };
  return build(flat.rootCID);
}

function layoutMSTTree(root, width, height) {
  const levels = [];
  const visit = (node, depth) => {
    if (!levels[depth]) levels[depth] = [];
    levels[depth].push(node);
    (node.children || []).forEach((child) => visit(child, depth + 1));
  };
  visit(root, 0);
  const depthCount = Math.max(levels.length, 1);
  const vGap = Math.max(72, (height - 48) / Math.max(depthCount - 1, 1));
  levels.forEach((row, depth) => {
    const hGap = width / (row.length + 1);
    row.forEach((node, index) => {
      node._x = hGap * (index + 1);
      node._y = 28 + depth * vGap;
    });
  });
  return root;
}

function renderMSTVisualization(panel) {
  if (!(panel instanceof Element)) return;
  const dataEl = panel.querySelector('.mst-tree-data');
  const svg = panel.querySelector('svg.mst-viz-svg');
  if (!dataEl || !svg) return;

  let flat;
  try {
    flat = JSON.parse(dataEl.textContent || '{}');
  } catch (_) {
    svg.replaceChildren();
    const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    text.setAttribute('x', '24');
    text.setAttribute('y', '40');
    text.setAttribute('class', 'mst-viz-empty');
    text.textContent = 'Unable to parse tree data';
    svg.append(text);
    panel.dataset.uiRendered = '1';
    return;
  }

  const hierarchy = buildMSTHierarchy(flat);
  if (!hierarchy) {
    svg.replaceChildren();
    const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    text.setAttribute('x', '24');
    text.setAttribute('y', '40');
    text.setAttribute('class', 'mst-viz-empty');
    text.textContent = flat?.rootCID ? 'Root CID present, but no matching node payload' : 'Empty tree';
    svg.append(text);
    panel.dataset.uiRendered = '1';
    return;
  }

  // Allow re-render when HTMX swaps a new tree into the same panel shell.
  if (panel.dataset.uiRendered === '1' && panel.dataset.uiMstCid === (hierarchy.cid || '')) {
    return;
  }
  panel.dataset.uiMstCid = hierarchy.cid || '';

  const width = Math.max(panel.clientWidth || 640, 480);
  const height = 360;
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
  svg.setAttribute('width', '100%');
  svg.setAttribute('height', String(height));
  layoutMSTTree(hierarchy, width, height);

  const ns = 'http://www.w3.org/2000/svg';
  const rootGroup = document.createElementNS(ns, 'g');
  rootGroup.setAttribute('class', 'mst-viz-scene');

  const links = [];
  const nodes = [];
  const walk = (node) => {
    nodes.push(node);
    (node.children || []).forEach((child) => {
      links.push({ from: node, to: child, label: child.edgeLabel || '' });
      walk(child);
    });
  };
  walk(hierarchy);

  links.forEach((link) => {
    const path = document.createElementNS(ns, 'path');
    const midY = (link.from._y + link.to._y) / 2;
    path.setAttribute('d', `M${link.from._x},${link.from._y} C${link.from._x},${midY} ${link.to._x},${midY} ${link.to._x},${link.to._y}`);
    path.setAttribute('class', 'mst-viz-link');
    rootGroup.append(path);
    if (link.label) {
      const label = document.createElementNS(ns, 'text');
      label.setAttribute('x', String((link.from._x + link.to._x) / 2));
      label.setAttribute('y', String(midY - 4));
      label.setAttribute('class', 'mst-viz-edge-label');
      label.textContent = link.label.length > 18 ? `${link.label.slice(0, 16)}…` : link.label;
      rootGroup.append(label);
    }
  });

  nodes.forEach((node) => {
    const group = document.createElementNS(ns, 'g');
    group.setAttribute('transform', `translate(${node._x},${node._y})`);
    group.setAttribute('class', `mst-viz-node${node === hierarchy ? ' is-root' : ''}${node.children?.length ? '' : ' is-leaf'}`);
    const circle = document.createElementNS(ns, 'circle');
    circle.setAttribute('r', node === hierarchy ? '16' : '12');
    circle.setAttribute('class', 'mst-viz-circle');
    const label = document.createElementNS(ns, 'text');
    label.setAttribute('y', '32');
    label.setAttribute('class', 'mst-viz-label');
    label.textContent = shortCID(node.cid);
    const title = document.createElementNS(ns, 'title');
    title.textContent = `${node.cid || ''}\n${node.kind || 'node'} · level ${node.level ?? '?'}`;
    group.append(circle, label, title);
    rootGroup.append(group);
  });

  svg.replaceChildren(rootGroup);
  panel._mstVizGroup = rootGroup;
  panel._mstVizScale = 1;
  panel._mstVizTX = 0;
  panel._mstVizTY = 0;
  panel.dataset.uiRendered = '1';

  const applyTransform = () => {
    rootGroup.setAttribute(
      'transform',
      `translate(${panel._mstVizTX} ${panel._mstVizTY}) scale(${panel._mstVizScale})`,
    );
  };

  let dragging = false;
  let lastX = 0;
  let lastY = 0;
  svg.onpointerdown = (event) => {
    dragging = true;
    lastX = event.clientX;
    lastY = event.clientY;
    svg.setPointerCapture(event.pointerId);
  };
  svg.onpointermove = (event) => {
    if (!dragging) return;
    panel._mstVizTX += event.clientX - lastX;
    panel._mstVizTY += event.clientY - lastY;
    lastX = event.clientX;
    lastY = event.clientY;
    applyTransform();
  };
  svg.onpointerup = () => { dragging = false; };
  svg.onpointercancel = () => { dragging = false; };
  svg.onwheel = (event) => {
    event.preventDefault();
    const delta = event.deltaY < 0 ? 1.08 : 0.92;
    panel._mstVizScale = Math.min(3, Math.max(0.4, panel._mstVizScale * delta));
    applyTransform();
  };
}

function truncateJSONPreview(text, max = 64) {
  const value = String(text ?? '');
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}…`;
}

function jsonTypeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function appendJSONToken(parent, className, text) {
  const el = document.createElement('span');
  el.className = className;
  el.textContent = text;
  parent.append(el);
  return el;
}

function buildJSONTreeNode(value, key, depth) {
  const type = jsonTypeOf(value);
  const row = document.createElement('div');
  row.className = 'json-node';

  if (type === 'object' || type === 'array') {
    const entries = type === 'array'
      ? value.map((item, index) => [index, item])
      : Object.keys(value).map((k) => [k, value[k]]);
    const details = document.createElement('details');
    details.className = 'json-collection';
    details.open = depth < 2;
    const summary = document.createElement('summary');
    summary.className = 'json-summary';
    if (key !== undefined && key !== null) {
      appendJSONToken(summary, 'json-key', String(key));
      appendJSONToken(summary, 'json-punct', ': ');
    }
    appendJSONToken(summary, 'json-punct', type === 'array' ? '[' : '{');
    appendJSONToken(summary, 'json-meta', `${entries.length}`);
    appendJSONToken(summary, 'json-punct', type === 'array' ? ']' : '}');
    details.append(summary);
    const children = document.createElement('div');
    children.className = 'json-children';
    if (entries.length === 0) {
      appendJSONToken(children, 'json-meta', type === 'array' ? '[]' : '{}');
    } else {
      entries.forEach(([childKey, childValue]) => {
        children.append(buildJSONTreeNode(childValue, childKey, depth + 1));
      });
    }
    details.append(children);
    row.append(details);
    return row;
  }

  const leaf = document.createElement('div');
  leaf.className = 'json-leaf';
  if (key !== undefined && key !== null) {
    appendJSONToken(leaf, 'json-key', String(key));
    appendJSONToken(leaf, 'json-punct', ': ');
  }
  if (type === 'string') {
    appendJSONToken(leaf, 'json-string', JSON.stringify(value));
  } else if (type === 'number') {
    appendJSONToken(leaf, 'json-number', String(value));
  } else if (type === 'boolean') {
    appendJSONToken(leaf, 'json-boolean', value ? 'true' : 'false');
  } else if (type === 'null') {
    appendJSONToken(leaf, 'json-null', 'null');
  } else {
    appendJSONToken(leaf, 'json-meta', truncateJSONPreview(String(value)));
  }
  row.append(leaf);
  return row;
}

function setJSONViewerMode(viewer, mode) {
  const tree = viewer.querySelector('[data-json-tree]');
  const raw = viewer.querySelector('[data-json-raw]');
  if (!tree || !raw) return;
  const showRaw = mode === 'raw';
  tree.hidden = showRaw;
  raw.hidden = !showRaw;
  viewer.querySelectorAll('[data-json-mode]').forEach((btn) => {
    const active = btn.getAttribute('data-json-mode') === mode;
    btn.classList.toggle('is-active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
  });
  viewer.querySelectorAll('[data-json-action="expand"], [data-json-action="collapse"]').forEach((btn) => {
    btn.hidden = showRaw;
  });
}

async function copyJSONViewerRaw(viewer, button) {
  const raw = viewer.querySelector('[data-json-raw]');
  const text = raw?.textContent || '';
  const label = button?.textContent || 'Copy';
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.left = '-9999px';
      document.body.append(area);
      area.select();
      document.execCommand('copy');
      area.remove();
    }
    if (button) {
      button.textContent = 'Copied';
      window.setTimeout(() => {
        button.textContent = label;
      }, 1200);
    }
  } catch (_) {
    if (button) {
      button.textContent = 'Copy failed';
      window.setTimeout(() => {
        button.textContent = label;
      }, 1200);
    }
  }
}

function hydrateJSONViewers(root) {
  if (!root || !root.querySelectorAll) return;
  const viewers = [];
  if (root.matches?.('[data-json-viewer]')) viewers.push(root);
  root.querySelectorAll('[data-json-viewer]').forEach((viewer) => viewers.push(viewer));
  viewers.forEach((viewer) => {
    if (viewer.dataset.jsonHydrated === '1') return;
    const tree = viewer.querySelector('[data-json-tree]');
    const raw = viewer.querySelector('[data-json-raw]');
    if (!tree || !raw) return;
    viewer.dataset.jsonHydrated = '1';
    let parsed;
    try {
      parsed = JSON.parse(raw.textContent || '{}');
    } catch (_) {
      tree.replaceChildren();
      const err = document.createElement('div');
      err.className = 'text-secondary text-sm';
      err.textContent = 'Unable to parse JSON; showing raw.';
      tree.append(err);
      setJSONViewerMode(viewer, 'raw');
      return;
    }
    tree.replaceChildren(buildJSONTreeNode(parsed, null, 0));
    setJSONViewerMode(viewer, 'tree');
  });
}

function hydrateUIWidgets(root) {
  if (!root) return;
  hydrateMSTVisualizations(root);
  hydrateJSONViewers(root);
  // HTMX may report the triggering element as target; also scan a nearby pane.
  if (root instanceof Element) {
    const pane = root.closest('.tab-pane');
    if (pane && pane !== root) {
      hydrateMSTVisualizations(pane);
      hydrateJSONViewers(pane);
    }
  }
}

function hydrateMSTVisualizations(root) {
  const scope = root instanceof Element ? root : document;
  scope.querySelectorAll?.('[data-ui-mst-viz]')?.forEach(renderMSTVisualization);
  if (scope.matches?.('[data-ui-mst-viz]')) renderMSTVisualization(scope);
}

async function handleAction(element) {
  const action = element.dataset.uiAction;
  switch (action) {
    case 'switch-tab':
      switchTab(element.dataset.tab);
      break;
    case 'mst-viz-reset': {
      const panel = element.closest('[data-ui-mst-viz]');
      if (!panel) break;
      panel._mstVizScale = 1;
      panel._mstVizTX = 0;
      panel._mstVizTY = 0;
      if (panel._mstVizGroup) {
        panel._mstVizGroup.setAttribute('transform', 'translate(0 0) scale(1)');
      }
      break;
    }
    case 'disable-invites':
      await postHTML('/admin/actions/disable-invites', { account: byID('disable-account')?.value || '' }, byID('invite-action-result'), '/admin/partials/invites', '#invites');
      break;
    case 'enable-invites':
      await postHTML('/admin/actions/enable-invites', { account: byID('enable-account')?.value || '' }, byID('invite-action-result'), '/admin/partials/invites', '#invites');
      break;
    case 'request-crawl':
      await postHTML('/admin/actions/request-crawl', { hostname: byID('crawl-hostname')?.value || '' }, byID('crawl-result'), '/admin/partials/relay-upstreams', '#relay-upstreams');
      break;
    case 'relay-reconnect-all':
      await postHTML('/admin/actions/relay-reconnect-all', {}, byID('relay-action-result'), '/admin/partials/relay-sources', '#relay-sources');
      break;
    case 'relay-disconnect-all':
      await postHTML('/admin/actions/relay-disconnect-all', {}, byID('relay-action-result'), '/admin/partials/relay-sources', '#relay-sources');
      break;
    case 'bulk-action': {
      const dids = Array.from(document.querySelectorAll('.account-checkbox:checked')).map((checkbox) => checkbox.value);
      if (dids.length === 0 || !window.confirm(`Apply ${element.dataset.uiActionKind} to ${dids.length} accounts?`)) return;
      const response = await adminRequest(`/admin/actions/bulk-${element.dataset.uiActionKind}`, { dids });
      const result = await response.json();
      window.alert(result.message || (result.success ? 'Success' : 'Failed'));
      reloadPartial('/admin/partials/accounts', '#accounts');
      break;
    }
    case 'toggle-select-all':
      document.querySelectorAll('.account-checkbox').forEach((checkbox) => { checkbox.checked = element.checked; });
      break;
    case 'delete-account':
      if (window.confirm('Are you sure you want to delete this account?')) {
        await postHTML('/admin/actions/delete-account', { did: element.dataset.uiDid || '' }, byID('account-detail-result'));
      }
      break;
    case 'rebuild-appview-scope':
      if (window.confirm('Rebuild the entire AppView relevance set?')) {
        await postHTML('/admin/actions/appview-rebuild-scope', {}, byID('appview-result'));
      }
      break;
    case 'appview-retry-repo':
      await postHTML('/admin/actions/appview-retry-repo', { did: element.dataset.uiDid || '' }, byID('appview-result'), '/admin/partials/appview-queue', '#appview-queue');
      break;
    case 'appview-cancel-repo':
      await postHTML('/admin/actions/appview-cancel-repo', { did: element.dataset.uiDid || '' }, byID('appview-result'), '/admin/partials/appview-queue', '#appview-queue');
      break;
    case 'resolve-pds-report':
      if (element.value) await postHTML('/admin/actions/resolve-pds-report', { reportID: element.dataset.uiReportId || '', action: element.value }, byID('pds-reports-result'));
      break;
    case 'remove-team-member':
      await postHTML('/admin/actions/remove-team-member', { did: element.dataset.uiDid || '' }, byID('ozone-team'), '/admin/partials/ozone-team', '#ozone-team');
      break;
    case 'delete-ozone-set':
      await postHTML('/admin/actions/delete-ozone-set', { name: element.dataset.uiName || '' }, byID('ozone-sets'), '/admin/partials/ozone-sets', '#ozone-sets');
      break;
    case 'delete-ozone-template':
      await postHTML('/admin/actions/delete-ozone-template', { name: element.dataset.uiName || '' }, byID('ozone-templates'), '/admin/partials/ozone-templates', '#ozone-templates');
      break;
    case 'revoke-session':
      await postHTML('/admin/actions/revoke-session', { did: element.dataset.uiDid || '', id: element.dataset.uiSessionId || '' }, byID('sessions-result'));
      break;
    case 'delete-app-password':
      await postHTML('/admin/actions/delete-app-password', { did: element.dataset.uiDid || '', name: element.dataset.uiName || '' }, byID('app-passwords-result'));
      break;
    case 'lock-chat-convo':
      if (window.confirm('Lock this conversation?')) await postHTML('/admin/actions/lock-chat-convo', { convoID: element.dataset.uiConvoId || '' }, byID('chat-action-result'), '/admin/partials/chat-convos', '#chat-convos');
      break;
    case 'cancel-scheduled-action':
      if (window.confirm('Cancel this scheduled action?')) await postHTML('/admin/actions/ozone-cancel-scheduled', { subjects: [element.dataset.uiSubject || ''] }, null, '/admin/partials/ozone-scheduled', '#ozone-scheduled');
      break;
    case 'revoke-ozone-verification':
      if (window.confirm('Revoke verification for this account?')) await postHTML('/admin/actions/ozone-revoke-verification', { dids: [element.dataset.uiDid || ''] }, null, '/admin/partials/ozone-verification', '#ozone-verification');
      break;
    case 'remove-safelink-rule':
      if (window.confirm('Remove this safelink rule?')) await postHTML('/admin/actions/remove-safelink-rule', { url: element.dataset.uiUrl || '', pattern: element.dataset.uiPattern || '' }, null, '/admin/partials/ozone-safelinks', '#ozone-safelinks');
      break;
    case 'export-mst': {
      const did = byID('mst-export-did')?.value || '';
      const format = byID('mst-export-format')?.value || 'json';
      window.open(`/admin/actions/mst-export?did=${encodeURIComponent(did)}&format=${encodeURIComponent(format)}`, '_blank', 'noopener');
      break;
    }
    case 'load-chat-messages': {
      const convoID = byID('chat-convo-id')?.value || '';
      if (convoID) reloadPartial(`/admin/partials/chat-messages?convoID=${encodeURIComponent(convoID)}`, '#chat-messages');
      break;
    }
    case 'filter-video-jobs':
      reloadPartial(`/admin/partials/video-jobs${element.dataset.uiState ? `?state=${encodeURIComponent(element.dataset.uiState)}` : ''}`, videoJobsContentTarget());
      break;
    case 'view-video-job': {
      const jobId = element.dataset.uiJobId || '';
      if (jobId) reloadPartial(`/admin/partials/video-job-detail?jobId=${encodeURIComponent(jobId)}`, videoJobsContentTarget());
      break;
    }
    case 'load-video-job-detail': {
      const jobId = byID('video-job-id')?.value || '';
      if (jobId) reloadPartial(`/admin/partials/video-job-detail?jobId=${encodeURIComponent(jobId)}`, videoJobsContentTarget());
      break;
    }
    case 'retry-video-job':
      if (window.confirm('Retry this job?')) await postHTML('/admin/actions/video-retry-job', { jobId: element.dataset.uiJobId || '' }, null, '/admin/partials/video-jobs', videoJobsContentTarget());
      break;
    case 'test-connection':
      await testConnection(element.dataset.uiService || '');
      break;
    default:
      break;
  }
}

async function handleForm(form) {
  switch (form.dataset.uiForm) {
    case 'login': {
      const response = await adminRequest('/admin/login', { password: byID('password')?.value || '' });
      if (response.ok) {
        window.location.assign('/admin');
        return;
      }
      let message = 'Invalid credentials';
      try {
        const body = await response.json();
        if (body?.error === 'invalid_csrf_token') {
          message = 'Sign-in expired. Try again.';
        } else if (body?.error === 'invalid_credentials') {
          message = 'Invalid credentials';
        } else if (body?.error) {
          message = String(body.error);
        }
      } catch (_) {
        /* keep default */
      }
      const error = byID('error');
      if (error) error.textContent = message;
      break;
    }
    case 'logout':
      if ((await adminRequest('/admin/logout')).ok) window.location.assign('/admin/login');
      break;
    case 'enqueue-backfill': {
      const dids = (byID('enqueue-dids-input')?.value || '').split('\n').map((did) => did.trim()).filter(Boolean);
      if (dids.length) {
        await postHTML('/admin/actions/appview-enqueue-dids', { dids }, byID('appview-result'), '/admin/partials/appview-queue', '#appview-queue');
      }
      break;
    }
    case 'load-blobs': {
      const did = byID('blob-did-input')?.value || '';
      if (did) reloadPartial(`/admin/partials/blobs?did=${encodeURIComponent(did)}`, '#blobs-content');
      break;
    }
    case 'add-ozone-team-member':
      await postHTML('/admin/actions/add-ozone-team-member', { member: { did: byID('add-member-did')?.value || '', role: byID('add-member-role')?.value || 'moderator' } }, byID('ozone-team'), '/admin/partials/ozone-team', '#ozone-team');
      break;
    case 'upsert-ozone-set':
      await postHTML('/admin/actions/upsert-ozone-set', { setSpec: { name: byID('create-set-name')?.value || '', description: byID('create-set-desc')?.value || '' } }, byID('ozone-sets'), '/admin/partials/ozone-sets', '#ozone-sets');
      break;
    case 'create-ozone-template':
      await postHTML('/admin/actions/create-ozone-template', { template: { name: byID('create-template-name')?.value || '', subject: byID('create-template-subject')?.value || '', contentMarkdown: byID('create-template-content')?.value || '' } }, byID('ozone-templates'), '/admin/partials/ozone-templates', '#ozone-templates');
      break;
    case 'update-ozone-config':
      try {
        await postHTML('/admin/actions/update-ozone-config', { config: JSON.parse(byID('config-json')?.value || '{}') }, byID('ozone-config-result'));
      } catch (_) {
        showError(byID('ozone-config-result'), 'Invalid JSON configuration.');
      }
      break;
    case 'create-app-password':
      await postHTML('/admin/actions/create-app-password', { did: byID('create-pwd-did')?.value || '', name: byID('create-pwd-name')?.value || '' }, byID('app-passwords-result'));
      break;
    case 'schedule-ozone-action':
      await postHTML('/admin/actions/ozone-schedule-action', { subject: byID('schedule-subject-did')?.value || '', action: byID('schedule-action-type')?.value || 'takedown' }, null, '/admin/partials/ozone-scheduled', '#ozone-scheduled');
      break;
    case 'grant-ozone-verification':
      await postHTML('/admin/actions/ozone-grant-verification', { did: byID('grant-verification-did')?.value || '', displayName: byID('grant-verification-name')?.value || '' }, null, '/admin/partials/ozone-verification', '#ozone-verification');
      break;
    case 'add-safelink-rule':
      await postHTML('/admin/actions/add-safelink-rule', { url: byID('add-safelink-url')?.value || '', pattern: byID('add-safelink-pattern')?.value || 'domain', action: byID('add-safelink-action')?.value || 'block', reason: byID('add-safelink-reason')?.value || 'none', comment: byID('add-safelink-comment')?.value || '' }, null, '/admin/partials/ozone-safelinks', '#ozone-safelinks');
      break;
    case 'find-ozone-related':
      await postHTML('/admin/actions/ozone-find-related', { did: byID('ozone-find-did')?.value || '' }, byID('ozone-signature-results'));
      break;
    case 'load-hosting-history': {
      const did = byID('hosting-did-input')?.value || '';
      if (did) reloadPartial(`/admin/partials/ozone-hosting?did=${encodeURIComponent(did)}`, '#ozone-hosting');
      break;
    }
    case 'save-connections':
      await saveConnections();
      break;
    case 'plc-sync':
      await adminRequest('/admin/actions/plc-sync', { action: action.dataset.plcAction || '' });
      reloadPartial('/admin/partials/plc-metrics', '#plc-metrics');
      break;
    case 'relay-request-crawl':
      await postHTML('/admin/actions/request-crawl', { hostname: byID('relay-crawl-hostname')?.value || '' }, byID('relay-action-result'), '/admin/partials/relay-sources', '#relay-sources');
      break;
    default:
      break;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const initial = Array.from(document.querySelectorAll('.tab-pane')).find((pane) => !pane.hidden);
  if (initial?.id?.startsWith('tab-')) {
    switchTab(initial.id.slice(4));
  }
});

// Nested placeholders arrive inside swapped tab HTML (Ozone/MST). Load them
// once; never rely on IntersectionObserver "revealed".
document.body.addEventListener('htmx:afterSwap', (event) => {
  const target = event.detail?.target;
  if (!(target instanceof Element)) return;
  const pane = target.closest('.tab-pane');
  // Lazy partials only when the owning pane is visible.
  if (pane && !pane.hidden) {
    loadLazyPartials(target);
  }
  // Widget hydration must not depend on tab visibility — swap targets can be
  // nested fragments, and MST/JSON payloads need to render immediately.
  hydrateUIWidgets(target);
});

document.body.addEventListener('htmx:afterSettle', (event) => {
  const target = event.detail?.target;
  if (!(target instanceof Element)) return;
  hydrateUIWidgets(target);
});

document.addEventListener('click', (event) => {
  const modeBtn = event.target.closest('[data-json-mode]');
  if (modeBtn) {
    const viewer = modeBtn.closest('[data-json-viewer]');
    if (viewer) {
      event.preventDefault();
      if (viewer.dataset.jsonHydrated !== '1') {
        hydrateJSONViewers(viewer);
      }
      setJSONViewerMode(viewer, modeBtn.getAttribute('data-json-mode') || 'tree');
      return;
    }
  }
  const jsonAction = event.target.closest('[data-json-action]');
  if (jsonAction) {
    const viewer = jsonAction.closest('[data-json-viewer]');
    if (viewer) {
      event.preventDefault();
      if (viewer.dataset.jsonHydrated !== '1') {
        hydrateJSONViewers(viewer);
      }
      const action = jsonAction.getAttribute('data-json-action');
      if (action === 'expand') {
        viewer.querySelectorAll('details.json-collection').forEach((el) => {
          el.open = true;
        });
      } else if (action === 'collapse') {
        viewer.querySelectorAll('details.json-collection').forEach((el) => {
          el.open = false;
        });
      } else if (action === 'copy') {
        copyJSONViewerRaw(viewer, jsonAction).catch(() => {});
      }
      return;
    }
  }
  const action = event.target.closest('[data-ui-action]');
  if (action) {
    event.preventDefault();
    handleAction(action).catch(() => showError(byID('footer-status'), 'The requested action failed.'));
    return;
  }
  if (event.target.closest('button,a,input,select,textarea,label')) return;
  const did = didFromText(event.target.closest('td,span,li,code,pre,div')?.textContent);
  fillVisibleDIDInputs(did);
});

document.addEventListener('change', (event) => {
  const action = event.target.closest('[data-ui-action="resolve-pds-report"]');
  if (action) handleAction(action).catch(() => showError(byID('pds-reports-result'), 'Unable to resolve report.'));
});

document.addEventListener('submit', (event) => {
  const form = event.target.closest('form[data-ui-form]');
  if (!form) return;
  event.preventDefault();
  handleForm(form).catch(() => showError(byID('footer-status'), 'The requested action failed.'));
});
