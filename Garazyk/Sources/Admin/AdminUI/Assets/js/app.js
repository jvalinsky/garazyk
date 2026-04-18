/**
 * AT Protocol Admin UI - Main Application Script
 *
 * Handles:
 * - Service segment switching (PDS, PLC, Relay, AppView, Chat)
 * - Sidebar section collapse/expand
 * - HTMX event handling
 * - Keyboard navigation
 * - Status bar updates
 */

(function() {
  'use strict';

  // ============================================
  // Service Segment Control
  // ============================================

  const services = ['pds', 'plc', 'relay', 'appview', 'chat'];
  let activeService = 'pds';

  function switchService(service) {
    if (!services.includes(service)) return;

    activeService = service;

    // Update segment buttons
    document.querySelectorAll('.service-segment').forEach(btn => {
      const isActive = btn.dataset.service === service;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    // Show/hide sidebar sections
    document.querySelectorAll('.sidebar-section').forEach(section => {
      const sectionService = section.dataset.service;
      const isCurrentService = sectionService === service;

      // Show section for current service, hide others
      section.style.display = isCurrentService ? 'block' : 'none';

      // Expand current service section
      if (isCurrentService) {
        const items = section.querySelector('.sidebar-items');
        const toggle = section.querySelector('.sidebar-section-toggle');
        if (items && toggle) {
          items.classList.remove('hidden');
          toggle.setAttribute('aria-expanded', 'true');
        }
      }
    });

    // Load default content for service
    const defaultRoutes = {
      pds: '/admin/users',
      plc: '/admin/plc/lookup',
      relay: '/admin/relay/upstreams',
      appview: '/admin/appview/backfill',
      chat: '/admin/chat'
    };

    if (defaultRoutes[service]) {
      htmx.ajax('GET', defaultRoutes[service], {
        target: '#content-pane',
        pushUrl: true
      });
    }

    // Update URL
    const url = new URL(window.location);
    url.searchParams.set('service', service);
    window.history.replaceState({}, '', url);
  }

  // Service segment click handlers
  document.querySelectorAll('.service-segment').forEach(btn => {
    btn.addEventListener('click', () => {
      switchService(btn.dataset.service);
    });
  });

  // ============================================
  // Sidebar Section Collapse/Expand
  // ============================================

  document.querySelectorAll('.sidebar-section-title').forEach(title => {
    title.addEventListener('click', (e) => {
      const section = title.closest('.sidebar-section');
      const items = section.querySelector('.sidebar-items');
      const toggle = title.querySelector('.sidebar-section-toggle');

      if (items) {
        const isHidden = items.classList.contains('hidden');
        items.classList.toggle('hidden');
        toggle.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
      }
    });
  });

  // Sidebar item click - mark active
  document.querySelectorAll('.sidebar-item').forEach(item => {
    item.addEventListener('click', () => {
      document.querySelectorAll('.sidebar-item').forEach(i => {
        i.classList.remove('active');
      });
      item.classList.add('active');
    });
  });

  // ============================================
  // HTMX Event Handlers
  // ============================================

  // Before request - show loading indicator
  document.body.addEventListener('htmx:beforeRequest', (e) => {
    const target = e.detail.target;
    if (target && target.id === 'content-pane') {
      target.classList.add('loading');
    }
  });

  // After request - hide loading indicator
  document.body.addEventListener('htmx:afterRequest', (e) => {
    const target = e.detail.target;
    if (target && target.id === 'content-pane') {
      target.classList.remove('loading');
    }
  });

  // After swap - update active sidebar item based on URL
  document.body.addEventListener('htmx:afterSwap', (e) => {
    // Re-apply event handlers to new content
    initializeContentHandlers();
  });

  // Response error handling
  document.body.addEventListener('htmx:responseError', (e) => {
    console.error('HTMX response error:', e.detail);
    const target = e.detail.target;
    if (target && target.id === 'content-pane') {
      target.innerHTML = `
        <div class="content-header">
          <h1>Error</h1>
        </div>
        <div class="alert alert-destructive">
          <div>
            <div class="alert-title">Request Failed</div>
            <div class="alert-message">
              HTTP ${e.detail.xhr?.status || 'Unknown'}: ${e.detail.error || 'An error occurred'}
            </div>
          </div>
        </div>
      `;
    }
  });

  // ============================================
  // Keyboard Navigation
  // ============================================

  document.addEventListener('keydown', (e) => {
    // Cmd/Ctrl + 1-5 to switch services
    if ((e.metaKey || e.ctrlKey) && e.key >= '1' && e.key <= '5') {
      e.preventDefault();
      const index = parseInt(e.key) - 1;
      if (services[index]) {
        switchService(services[index]);
      }
    }

    // Escape to close dialogs
    if (e.key === 'Escape') {
      const dialogs = document.querySelectorAll('dialog[open]');
      dialogs.forEach(dialog => dialog.close());
    }
  });

  // ============================================
  // Content Area Handlers
  // ============================================

  function initializeContentHandlers() {
    // Table row click handlers
    document.querySelectorAll('.table tbody tr[data-action]').forEach(row => {
      row.addEventListener('click', () => {
        const action = row.dataset.action;
        if (action) {
          htmx.ajax('GET', action, {
            target: '#detail-panel',
            swap: 'innerHTML'
          });
        }
      });
    });

    // Form submit handlers
    document.querySelectorAll('form[data-ajax]').forEach(form => {
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const action = form.action;
        const method = form.method || 'POST';
        const formData = new FormData(form);

        htmx.ajax(method, action, {
          target: form.dataset.target || '#content-pane',
          values: Object.fromEntries(formData)
        });
      });
    });

    // Confirm dialog for destructive actions
    document.querySelectorAll('[data-confirm]').forEach(el => {
      el.addEventListener('click', (e) => {
        const message = el.dataset.confirm;
        if (!confirm(message)) {
          e.preventDefault();
          e.stopImmediatePropagation();
        }
      });
    });
  }

  // ============================================
  // Status Bar
  // ============================================

  function updateLastSync() {
    const el = document.getElementById('last-sync');
    if (el) {
      const now = new Date();
      el.textContent = now.toLocaleTimeString();
    }
  }

  // Update last sync time every minute
  setInterval(updateLastSync, 60000);
  updateLastSync();

  // ============================================
  // Navigation Toggle (Mobile)
  // ============================================

  const navToggle = document.getElementById('nav-toggle');
  const sidebar = document.getElementById('sidebar');

  if (navToggle && sidebar) {
    navToggle.addEventListener('click', () => {
      sidebar.classList.toggle('collapsed');
    });
  }

  // ============================================
  // Initialization
  // ============================================

  function init() {
    // Check URL for service param
    const params = new URLSearchParams(window.location.search);
    const service = params.get('service');
    if (service && services.includes(service)) {
      switchService(service);
    } else {
      // Default to PDS
      switchService('pds');
    }

    // Initialize content handlers
    initializeContentHandlers();

    console.log('AT Protocol Admin UI initialized');
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
