// AT Protocol Admin UI - Client-side interactivity

'use strict';

import { AdminPanel } from './admin-panel.js';
import { AdminChat } from './admin-chat.js';
import { AdminOzone } from './admin-ozone.js';
import { AdminSecurity } from './admin-security.js';
import { AdminPlcSync } from './admin-plc-sync.js';

const CONFIG = {
  services: ['pds', 'plc', 'relay', 'appview', 'chat', 'ozone', 'security'],
  activeServiceKey: 'adminui_active_service',
  sidebarCollapsePrefix: 'sidebar_collapsed_',
  loadingSpinnerClass: 'htmx-temp-spinner',
};

const A11Y_STATUS_ID = 'admin-a11y-status';

function toggleHidden(element, shouldHide) {
  if (!element) return;
  element.classList.toggle('hidden', shouldHide);
  element.classList.toggle('is-hidden', shouldHide);
}

function announceStatus(message) {
  const status = document.getElementById(A11Y_STATUS_ID);
  if (status) {
    status.textContent = message;
  }
}

function escapeHTML(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

const AdminAuth = {
  getToken() {
    return sessionStorage.getItem('admin_token');
  },

  showLoginPanel() {
    const panel = document.getElementById('admin-login-panel');
    const input = document.getElementById('admin-password');
    const errorEl = document.getElementById('admin-login-error');

    toggleHidden(panel, false);
    if (input) {
      input.value = '';
      input.focus();
    }
    if (errorEl) {
      errorEl.textContent = '';
      errorEl.classList.remove('is-visible');
    }

    announceStatus('Admin sign-in required.');
  },

  hideLoginPanel() {
    const panel = document.getElementById('admin-login-panel');
    toggleHidden(panel, true);
  },

  async doLogin() {
    const passwordInput = document.getElementById('admin-password');
    const password = passwordInput?.value || '';
    const errorEl = document.getElementById('admin-login-error');

    if (!password.trim()) {
      if (errorEl) {
        errorEl.textContent = 'Password required.';
        errorEl.classList.add('is-visible');
      }
      if (passwordInput) {
        passwordInput.setAttribute('aria-invalid', 'true');
        passwordInput.focus();
      }
      return;
    }

    if (passwordInput) {
      passwordInput.removeAttribute('aria-invalid');
    }

    try {
      const resp = await fetch('/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      });

      const data = await resp.json();

      if (resp.ok && data.token) {
        sessionStorage.setItem('admin_token', data.token);
        this.hideLoginPanel();
        announceStatus('Admin login successful. Reloading dashboard.');
        window.location.reload();
        return;
      }

      if (errorEl) {
        errorEl.textContent = data.error || 'Login failed.';
        errorEl.classList.add('is-visible');
      }
      createNotification('destructive', data.error || 'Login failed.');
    } catch (_err) {
      if (errorEl) {
        errorEl.textContent = 'Connection error.';
        errorEl.classList.add('is-visible');
      }
      createNotification('destructive', 'Connection error while logging in.');
    }
  },
};

window.AdminAuth = AdminAuth;

function getAdminToken() {
  return sessionStorage.getItem('admin_token') || AdminAuth.getToken();
}

function getVisibleServiceSegments() {
  return Array.from(document.querySelectorAll('.service-segment'));
}

function setActiveServiceSegment(service, focusSegment = false) {
  const segments = getVisibleServiceSegments();
  segments.forEach((seg) => {
    const isActive = seg.dataset.service === service;
    seg.classList.toggle('active', isActive);
    seg.setAttribute('aria-selected', isActive ? 'true' : 'false');
    if (isActive && focusSegment) {
      seg.focus();
    }
  });
}

function setSidebarServiceVisibility(service) {
  document.querySelectorAll('.sidebar-section').forEach((section) => {
    const shouldHide = section.dataset.service !== service;
    section.classList.toggle('is-hidden', shouldHide);
  });
}

function switchToService(service, options = {}) {
  const focusSegment = options.focusSegment === true;
  if (!CONFIG.services.includes(service)) return;

  setActiveServiceSegment(service, focusSegment);
  setSidebarServiceVisibility(service);
  localStorage.setItem(CONFIG.activeServiceKey, service);

  const activeSidebarItem = document.querySelector('.sidebar-section:not(.is-hidden) .sidebar-item.active');
  if (!activeSidebarItem) {
    const firstVisible = document.querySelector('.sidebar-section:not(.is-hidden) .sidebar-item');
    if (firstVisible) {
      firstVisible.classList.add('active');
    }
  }

  announceStatus(`Service switched to ${service.toUpperCase()}.`);
}

function initServiceSwitching() {
  getVisibleServiceSegments().forEach((segment) => {
    segment.addEventListener('click', (evt) => {
      evt.preventDefault();
      switchToService(segment.dataset.service);
    });
  });

  const savedService = localStorage.getItem(CONFIG.activeServiceKey) || 'pds';
  switchToService(savedService);
}

function initServiceKeyboardNavigation() {
  document.addEventListener('keydown', (evt) => {
    const focused = document.activeElement;
    const segments = getVisibleServiceSegments();
    if (!focused || !focused.classList.contains('service-segment')) return;

    const currentIndex = segments.indexOf(focused);
    if (currentIndex < 0) return;

    if (evt.key === 'ArrowRight') {
      evt.preventDefault();
      const nextIndex = (currentIndex + 1) % segments.length;
      switchToService(segments[nextIndex].dataset.service, { focusSegment: true });
    }

    if (evt.key === 'ArrowLeft') {
      evt.preventDefault();
      const nextIndex = (currentIndex - 1 + segments.length) % segments.length;
      switchToService(segments[nextIndex].dataset.service, { focusSegment: true });
    }
  });
}

function initSidebarSections() {
  document.querySelectorAll('.sidebar-section-title').forEach((title) => {
    title.addEventListener('click', (evt) => {
      evt.preventDefault();
      const controlsId = title.getAttribute('aria-controls');
      const itemsDiv = document.getElementById(controlsId);
      if (!itemsDiv) return;

      const isExpanded = title.getAttribute('aria-expanded') === 'true';
      title.setAttribute('aria-expanded', isExpanded ? 'false' : 'true');
      toggleHidden(itemsDiv, isExpanded);

      const toggleIcon = title.querySelector('.sidebar-section-toggle');
      if (toggleIcon) {
        toggleIcon.setAttribute('aria-expanded', title.getAttribute('aria-expanded') || 'false');
      }

      if (isExpanded) {
        localStorage.setItem(CONFIG.sidebarCollapsePrefix + controlsId, 'true');
      } else {
        localStorage.removeItem(CONFIG.sidebarCollapsePrefix + controlsId);
      }
    });
  });

  document.querySelectorAll('.sidebar-items').forEach((items) => {
    const id = items.id;
    const collapsed = Boolean(localStorage.getItem(CONFIG.sidebarCollapsePrefix + id));
    toggleHidden(items, collapsed);

    const title = document.querySelector(`.sidebar-section-title[aria-controls="${id}"]`);
    if (title) {
      title.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      const toggleIcon = title.querySelector('.sidebar-section-toggle');
      if (toggleIcon) {
        toggleIcon.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      }
    }
  });
}

function activateSidebarItem(item) {
  const sectionItems = item.closest('.sidebar-items');
  if (!sectionItems) return;

  sectionItems.querySelectorAll('.sidebar-item').forEach((candidate) => {
    candidate.classList.remove('active');
  });
  item.classList.add('active');
}

function initSidebarActive() {
  const currentPath = window.location.pathname;
  document.querySelectorAll('.sidebar-item').forEach((item) => {
    const pushURL = item.getAttribute('hx-push-url');
    if (pushURL && pushURL === currentPath) {
      activateSidebarItem(item);
    }

    if (!item.dataset.boundActive) {
      item.addEventListener('click', () => activateSidebarItem(item));
      item.dataset.boundActive = 'true';
    }
  });
}

function initNavToggle() {
  const navToggle = document.getElementById('nav-toggle');
  const sidebar = document.querySelector('aside[role="complementary"]');
  if (!navToggle || !sidebar) return;

  navToggle.addEventListener('click', (evt) => {
    evt.preventDefault();
    const isHidden = sidebar.classList.toggle('is-hidden');
    navToggle.setAttribute('aria-expanded', isHidden ? 'false' : 'true');
  });
}

function getRequestTarget(detail) {
  const targetSelector = typeof detail?.target === 'string' ? detail.target : null;
  if (targetSelector) return document.querySelector(targetSelector);
  return detail?.target || null;
}

function addLoadingSpinner(target) {
  if (!target || !target.parentElement) return;
  if (target.parentElement.querySelector(`.${CONFIG.loadingSpinnerClass}`)) return;

  const spinner = document.createElement('div');
  spinner.className = `loading-indicator ${CONFIG.loadingSpinnerClass}`;
  spinner.setAttribute('aria-hidden', 'true');
  target.parentElement.appendChild(spinner);
}

function removeLoadingSpinner(target) {
  const container = target?.parentElement || document;
  container.querySelectorAll(`.${CONFIG.loadingSpinnerClass}`).forEach((spinner) => spinner.remove());
}

function buildAuthRequiredMarkup() {
  return `<div class="empty-state empty-state-auth" role="alert">
    <div class="empty-state-icon">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
        <rect x="3" y="11" width="18" height="11" rx="2"></rect>
        <path d="M7 11V7a5 5 0 0 1 10 0v4"></path>
      </svg>
    </div>
    <h3 class="empty-state-title">Sign In Required</h3>
    <p class="empty-state-description">You must be authenticated to view this resource.</p>
    <div class="empty-state-actions">
      <button class="btn btn-primary" data-action="show-login-panel">Sign In</button>
    </div>
  </div>`;
}

function createNotification(type, message, timeoutMs = 5000) {
  const contentPane = document.getElementById('content-pane');
  if (!contentPane) return;

  const alert = document.createElement('div');
  alert.className = `alert alert-${type}`;
  alert.setAttribute('role', type === 'destructive' ? 'alert' : 'status');
  alert.innerHTML = `
    <span>${escapeHTML(message)}</span>
    <button class="btn-close-inline" data-action="dismiss-alert" aria-label="Close">×</button>
  `;

  contentPane.insertBefore(alert, contentPane.firstChild);
  if (timeoutMs > 0) {
    window.setTimeout(() => alert.remove(), timeoutMs);
  }
}

function showErrorNotification(message) {
  createNotification('destructive', message, 6000);
  announceStatus(`Error: ${message}`);
}

function showSuccessNotification(message) {
  createNotification('success', message, 3500);
  announceStatus(message);
}

const SheetDialog = {
  activeSheet: null,

  open(options) {
    const {
      title,
      fields = [],
      confirmLabel = 'Confirm',
      cancelLabel = 'Cancel',
      confirmStyle = 'btn-primary',
      onConfirm,
      onCancel,
      initialValues = {}
    } = options;

    this.close();

    const sheet = document.createElement('dialog');
    sheet.className = 'sheet-dialog';
    sheet.id = 'sheet-dialog-' + Date.now();

    const fieldsHTML = fields.map((field, idx) => {
      const value = initialValues[field.name] ?? field.value ?? '';
      const required = field.required ? 'required' : '';
      const placeholder = field.placeholder ? `placeholder="${field.placeholder}"` : '';
      const pattern = field.pattern ? `pattern="${field.pattern}"` : '';
      const rows = field.type === 'textarea' ? `rows="${field.rows || 4}"` : '';

      if (field.type === 'description') {
        return `<div class="sheet-dialog-message">${escapeHTML(value || field.value)}</div>`;
      }

      if (field.type === 'textarea') {
        return `<div class="form-group">
          <label class="form-label" for="${sheet.id}-field-${idx}">${field.label}</label>
          <textarea class="form-input" id="${sheet.id}-field-${idx}" name="${field.name}" ${required} ${placeholder} ${rows}>${escapeHTML(value)}</textarea>
        </div>`;
      }

      if (field.type === 'select') {
        const opts = (field.options || []).map(o =>
          `<option value="${o.value}" ${o.value === value ? 'selected' : ''}>${o.label}</option>`
        ).join('');
        return `<div class="form-group">
          <label class="form-label" for="${sheet.id}-field-${idx}">${field.label}</label>
          <select class="form-input" id="${sheet.id}-field-${idx}" name="${field.name}" ${required}>
            ${opts}
          </select>
        </div>`;
      }

      if (field.type === 'checkbox') {
        return `<div class="form-group form-checkbox">
          <input type="checkbox" id="${sheet.id}-field-${idx}" name="${field.name}" ${value ? 'checked' : ''} ${required}>
          <label for="${sheet.id}-field-${idx}">${field.label}</label>
        </div>`;
      }

      return `<div class="form-group">
        <label class="form-label" for="${sheet.id}-field-${idx}">${field.label}</label>
        <input class="form-input" type="${field.type || 'text'}" id="${sheet.id}-field-${idx}" name="${field.name}" value="${escapeHTML(value)}" ${required} ${placeholder} ${pattern}>
      </div>`;
    }).join('');

    sheet.innerHTML = `
      <div class="sheet-dialog-content">
        <div class="sheet-dialog-header">
          <h3 class="sheet-dialog-title">${escapeHTML(title)}</h3>
          <button type="button" class="btn-close-inline" data-action="close-sheet" aria-label="Close">×</button>
        </div>
        <form class="sheet-dialog-form">
          ${fieldsHTML}
          <div class="sheet-dialog-actions">
            <button type="button" class="btn" data-action="cancel-sheet">${escapeHTML(cancelLabel)}</button>
            <button type="submit" class="btn ${confirmStyle}">${escapeHTML(confirmLabel)}</button>
          </div>
        </form>
      </div>
    `;

    document.body.appendChild(sheet);

    const closeSheet = () => {
      sheet.close();
      sheet.remove();
      this.activeSheet = null;
    };

    sheet.addEventListener('click', (evt) => {
      if (evt.target === sheet) closeSheet();
    });

    sheet.addEventListener('keydown', (evt) => {
      if (evt.key === 'Escape') closeSheet();
    });

    const cancelBtn = sheet.querySelector('[data-action="cancel-sheet"]');
    if (cancelBtn) {
      cancelBtn.addEventListener('click', () => {
        if (onCancel) onCancel(getFormData(sheet));
        closeSheet();
      });
    }

    const form = sheet.querySelector('form');
    form.addEventListener('submit', (evt) => {
      evt.preventDefault();
      const data = getFormData(sheet);
      if (onConfirm) onConfirm(data);
      closeSheet();
    });

    sheet.showModal();
    this.activeSheet = sheet;

    const firstInput = sheet.querySelector('input, textarea, select');
    if (firstInput) firstInput.focus();

    return sheet;
  },

  confirm(options) {
    const {
      message,
      title = 'Confirm',
      confirmLabel = 'Confirm',
      cancelLabel = 'Cancel',
      onConfirm,
      destructive = false
    } = options;

    this.open({
      title,
      fields: [{ type: 'description', label: '', value: message }],
      confirmLabel,
      cancelLabel,
      confirmStyle: destructive ? 'btn-danger' : 'btn-primary',
      onConfirm: () => { if (onConfirm) onConfirm(); }
    });
  },

  prompt(options) {
    const {
      label,
      title = 'Enter value',
      initialValue = '',
      placeholder = '',
      confirmLabel = 'OK',
      cancelLabel = 'Cancel',
      onConfirm,
      type = 'text'
    } = options;

    this.open({
      title,
      fields: [{ name: 'value', label, type, value: initialValue, placeholder }],
      confirmLabel,
      cancelLabel,
      onConfirm: (data) => { if (onConfirm) onConfirm(data.value); }
    });
  },

  close() {
    const openSheets = document.querySelectorAll('dialog.sheet-dialog[open]');
    openSheets.forEach(s => { s.close(); s.remove(); });
    this.activeSheet = null;
  }
};

function getFormData(sheet) {
  const form = sheet.querySelector('form');
  const data = {};
  const formData = new FormData(form);
  formData.forEach((value, key) => { data[key] = value; });

  sheet.querySelectorAll('[type="checkbox"]').forEach(cb => {
    data[cb.name] = cb.checked;
  });

  return data;
}

function toPartialPath(path) {
  if (!path || !path.startsWith('/admin/')) return path;
  if (path.startsWith('/admin/partials/')) return path;
  return path.replace('/admin/', '/admin/partials/');
}

function loadPartialPath(path) {
  const contentPane = document.getElementById('content-pane');
  if (!contentPane) return;

  const sidebarItem = document.querySelector(`.sidebar-item[hx-push-url="${path}"]`);
  if (sidebarItem) {
    sidebarItem.click();
    return;
  }

  const partialPath = toPartialPath(path);
  if (window.htmx) {
    window.htmx.ajax('GET', partialPath, '#content-pane');
  }
}

function initHTMXHandlers() {
  document.body.addEventListener('htmx:configRequest', (evt) => {
    const token = getAdminToken();
    if (!token) return;

    evt.detail.headers = evt.detail.headers || {};
    evt.detail.headers.Authorization = `Bearer ${token}`;
    evt.detail.headers['X-Admin-Token'] = token;
  });

  document.body.addEventListener('htmx:beforeRequest', (evt) => {
    const target = getRequestTarget(evt.detail);
    if (target) {
      target.classList.add('is-loading');
      addLoadingSpinner(target);
    }
  });

  document.body.addEventListener('htmx:afterRequest', (evt) => {
    const target = getRequestTarget(evt.detail);
    if (target) {
      target.classList.remove('is-loading');
      removeLoadingSpinner(target);
    }
  });

  document.body.addEventListener('htmx:beforeSwap', (evt) => {
    const target = evt.detail.target;
    if (!(target instanceof HTMLElement)) return;

    const scrollKey = 'scroll-' + target.id;
    const scrollData = {
      scrollTop: target.scrollTop,
      scrollLeft: target.scrollLeft,
      scrollHeight: target.scrollHeight
    };
    target.dataset.prevScroll = JSON.stringify(scrollData);
    target.dataset.prevScrollKey = scrollKey;
  });

  document.body.addEventListener('htmx:afterSwap', (evt) => {
    const target = evt.detail.target;
    if (target && target.dataset.prevScroll) {
      try {
        const scrollData = JSON.parse(target.dataset.prevScroll);
        if (scrollData.scrollHeight !== target.scrollHeight) {
          const maxScroll = target.scrollHeight - target.clientHeight;
          target.scrollTop = Math.min(scrollData.scrollTop, maxScroll);
        } else {
          target.scrollTop = scrollData.scrollTop;
        }
        target.scrollLeft = scrollData.scrollLeft;
      } catch (_e) {}
      delete target.dataset.prevScroll;
    }

    initSidebarActive();
    hydrateInteractiveContent(target || document);
  });

  document.body.addEventListener('htmx:responseError', (evt) => {
    const status = evt.detail?.xhr?.status;
    const statusText = evt.detail?.xhr?.statusText || 'Request failed';

    if (status === 401) {
      evt.preventDefault();
      const target = getRequestTarget(evt.detail) || document.getElementById('content-pane');
      if (!sessionStorage.getItem('admin_token')) {
        AdminAuth.showLoginPanel();
      }
      if (target) {
        target.innerHTML = buildAuthRequiredMarkup();
      }
      return;
    }

    showErrorNotification(`Error: ${status || 'Unknown'} ${statusText}`);
  });

  document.body.addEventListener('htmx:sendError', () => {
    showErrorNotification('Network error: could not reach server.');
  });
}

function initGlobalActions() {
  document.addEventListener('click', async (evt) => {
    const target = evt.target.closest('[data-action]');
    if (!target) return;

    const action = target.dataset.action;

    if (action === 'dismiss-alert') {
      evt.preventDefault();
      target.closest('.alert')?.remove();
      return;
    }

    if (action === 'hide-login-panel') {
      evt.preventDefault();
      AdminAuth.hideLoginPanel();
      return;
    }

    if (action === 'show-login-panel') {
      evt.preventDefault();
      AdminAuth.showLoginPanel();
      return;
    }

    if (action === 'close-dialog') {
      evt.preventDefault();
      const dialogId = target.dataset.dialog;
      const dialog = dialogId ? document.getElementById(dialogId) : target.closest('dialog');
      dialog?.close();
      return;
    }

    if (action === 'close-inspector') {
      evt.preventDefault();
      const Inspector = window.AdminUI?.Inspector;
      if (Inspector) Inspector.hide();
      return;
    }

    if (action === 'copy-to-clipboard') {
      evt.preventDefault();
      const value = target.dataset.value || '';
      try {
        await navigator.clipboard.writeText(value);
        showSuccessNotification('Copied to clipboard.');
      } catch (_err) {
        showErrorNotification('Could not copy to clipboard.');
      }
      return;
    }

    if (action === 'navigate-diagnostics') {
      evt.preventDefault();
      const path = target.dataset.path;
      if (path) loadPartialPath(path);
    }
  });

  document.addEventListener('keydown', (evt) => {
    if (evt.key === 'Escape') {
      const loginPanel = document.getElementById('admin-login-panel');
      if (loginPanel && !loginPanel.classList.contains('hidden') && !loginPanel.classList.contains('is-hidden')) {
        AdminAuth.hideLoginPanel();
      }
    }

    if ((evt.metaKey || evt.ctrlKey) && !evt.shiftKey && !evt.altKey) {
      const num = Number.parseInt(evt.key, 10);
      if (!Number.isNaN(num) && num >= 1 && num <= CONFIG.services.length) {
        evt.preventDefault();
        switchToService(CONFIG.services[num - 1], { focusSegment: true });
      }

      if (evt.key.toLowerCase() === 'f') {
        const searchInput = document.querySelector('input[type="search"], input[placeholder*="search" i]');
        if (searchInput) {
          evt.preventDefault();
          searchInput.focus();
        }
      }
    }
  });
}

function initStatusBar() {
  const lastSyncEl = document.getElementById('last-sync');
  if (!lastSyncEl) return;

  const updateLastSync = () => {
    const now = new Date();
    lastSyncEl.textContent = now.toLocaleTimeString();
  };

  updateLastSync();
  window.setInterval(updateLastSync, 60000);
}

function hydrateInteractiveContent(root = document) {
  const scope = root instanceof Element ? root : document;

  scope.querySelectorAll('dialog.modal').forEach((dialog) => {
    if (dialog.dataset.dialogBound === 'true') return;
    dialog.dataset.dialogBound = 'true';

    dialog.addEventListener('click', (evt) => {
      if (evt.target === dialog) dialog.close();
    });

    dialog.addEventListener('keydown', (evt) => {
      if (evt.key === 'Escape') dialog.close();
    });
  });

  scope.querySelectorAll('.table tbody tr').forEach((row) => {
    if (row.dataset.rowClickBound === 'true') return;
    row.dataset.rowClickBound = 'true';
    row.classList.add('cursor-pointer');

    row.addEventListener('click', (evt) => {
      if (evt.target.closest('button, a, input, label, select, textarea')) return;
      const actionBtn = row.querySelector('[hx-get], [hx-post], [hx-put], [hx-delete]');
      if (actionBtn) actionBtn.click();
    });
  });
}

function initFormHandlers() {
  document.addEventListener('focusout', (evt) => {
    const input = evt.target;
    if (!(input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement)) return;
    if (!input.classList.contains('form-input')) return;

    input.value = input.value.trim();
    if (input.hasAttribute('required') && !input.value) {
      input.setAttribute('aria-invalid', 'true');
    } else {
      input.removeAttribute('aria-invalid');
    }
  });

  document.addEventListener('submit', (evt) => {
    const form = evt.target;
    if (!(form instanceof HTMLFormElement) || !form.classList.contains('form')) return;

    const requiredInputs = form.querySelectorAll('[required]');
    let firstInvalid = null;

    requiredInputs.forEach((field) => {
      const value = (field.value || '').trim();
      if (!value) {
        field.setAttribute('aria-invalid', 'true');
        if (!firstInvalid) firstInvalid = field;
      } else {
        field.removeAttribute('aria-invalid');
      }
    });

    if (firstInvalid) {
      evt.preventDefault();
      firstInvalid.focus();
      showErrorNotification('Please fill in all required fields.');
    }
  });
}

function initLoginHandlers() {
  const loginBtn = document.getElementById('admin-login-btn');
  const passwordInput = document.getElementById('admin-password');

  if (loginBtn) {
    loginBtn.addEventListener('click', (evt) => {
      evt.preventDefault();
      AdminAuth.doLogin();
    });
  }

  if (passwordInput) {
    passwordInput.addEventListener('keydown', (evt) => {
      if (evt.key !== 'Enter') return;
      evt.preventDefault();
      AdminAuth.doLogin();
    });
  }
}

function initFeatureModules() {
  if (typeof AdminChat?.init === 'function') AdminChat.init();
  if (typeof AdminOzone?.init === 'function') AdminOzone.init();
  if (typeof AdminSecurity?.init === 'function') AdminSecurity.init();
  if (typeof AdminPlcSync?.init === 'function') AdminPlcSync.init();
  if (typeof AdminPanel?.init === 'function') AdminPanel.init();
}

function initAuthFallbackRendering() {
  document.addEventListener('htmx:afterSwap', (evt) => {
    const target = evt.detail?.target;
    if (!target || !(target instanceof HTMLElement)) return;

    const bodyText = (target.textContent || '').trim();
    if (!bodyText.includes('401')) return;
    target.innerHTML = buildAuthRequiredMarkup();
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initServiceSwitching();
  initServiceKeyboardNavigation();
  initSidebarSections();
  initSidebarActive();
  initNavToggle();
  initGlobalActions();
  initHTMXHandlers();
  initStatusBar();
  initFormHandlers();
  initLoginHandlers();
  initAuthFallbackRendering();
  hydrateInteractiveContent(document);
  initFeatureModules();
});

window.AdminUI = {
  showError: showErrorNotification,
  showSuccess: showSuccessNotification,
  switchService: switchToService,
  loadPartialPath,
  SheetDialog: SheetDialog,
  confirm: SheetDialog.confirm.bind(SheetDialog),
  prompt: SheetDialog.prompt.bind(SheetDialog),
  Inspector: {
    show(title, content) {
      const pane = document.getElementById('inspector-pane');
      const titleEl = document.getElementById('inspector-title');
      const contentEl = document.getElementById('inspector-content');
      if (!pane) return;
      if (titleEl) titleEl.textContent = title || 'Inspector';
      if (contentEl) contentEl.innerHTML = content;
      pane.hidden = false;
      pane.removeAttribute('hidden');
      announceStatus(`Inspector opened: ${title}`);
    },
    hide() {
      const pane = document.getElementById('inspector-pane');
      if (pane) {
        pane.hidden = true;
        pane.setAttribute('hidden', '');
      }
      announceStatus('Inspector closed');
    },
    updateContent(content) {
      const contentEl = document.getElementById('inspector-content');
      if (contentEl) contentEl.innerHTML = content;
    }
  }
};

window.navigateTo = function navigateTo(path) {
  if (path) {
    loadPartialPath(path);
  }
};
