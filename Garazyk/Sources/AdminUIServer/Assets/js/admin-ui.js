// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

const csrfNonceMeta = () => document.querySelector('meta[name="csrf-nonce"]');
const byID = (id) => document.getElementById(id);

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
  if (window.htmx) {
    window.htmx.ajax('GET', path, targetSelector);
    return;
  }
  fetch(path, { credentials: 'same-origin' })
    .then((response) => replaceServerHTML(document.querySelector(targetSelector), response))
    .catch(() => showError(document.querySelector(targetSelector), 'Unable to refresh data.'));
}

function switchTab(name) {
  document.querySelectorAll('.tab-pane').forEach((pane) => {
    pane.hidden = pane.id !== `tab-${name}`;
  });
  document.querySelectorAll('.service-segment').forEach((segment) => {
    segment.classList.toggle('active', segment.dataset.tab === name);
  });
}

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

async function handleAction(element) {
  const action = element.dataset.uiAction;
  switch (action) {
    case 'switch-tab':
      switchTab(element.dataset.tab);
      break;
    case 'disable-invites':
      await postHTML('/admin/actions/disable-invites', { account: byID('disable-account')?.value || '' }, byID('invite-action-result'), '/admin/partials/invites', '#invites');
      break;
    case 'enable-invites':
      await postHTML('/admin/actions/enable-invites', { account: byID('enable-account')?.value || '' }, byID('invite-action-result'), '/admin/partials/invites', '#invites');
      break;
    case 'request-crawl':
      await postHTML('/admin/actions/request-crawl', { hostname: byID('crawl-hostname')?.value || '' }, byID('crawl-result'), '/admin/partials/relay-upstreams', '#relay-upstreams');
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
      reloadPartial(`/admin/partials/video-jobs${element.dataset.uiState ? `?state=${encodeURIComponent(element.dataset.uiState)}` : ''}`, '#video-jobs');
      break;
    case 'load-video-job-detail': {
      const jobId = byID('video-job-id')?.value || '';
      if (jobId) reloadPartial(`/admin/partials/video-job-detail?jobId=${encodeURIComponent(jobId)}`, '#video-job-detail');
      break;
    }
    case 'retry-video-job':
      if (window.confirm('Retry this job?')) await postHTML('/admin/actions/video-retry-job', { jobId: element.dataset.uiJobId || '' }, byID('video-job-detail'), '/admin/partials/video-jobs', '#video-jobs');
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
      if (response.ok) window.location.assign('/admin');
      else byID('error').textContent = 'Invalid credentials';
      break;
    }
    case 'logout':
      if ((await adminRequest('/admin/logout')).ok) window.location.assign('/admin/login');
      break;
    case 'enqueue-backfill': {
      const dids = (byID('enqueue-dids-input')?.value || '').split('\n').map((did) => did.trim()).filter(Boolean);
      if (dids.length) await postHTML('/admin/actions/appview-enqueue-dids', { dids }, byID('appview-result'));
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
    default:
      break;
  }
}

document.addEventListener('click', (event) => {
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
