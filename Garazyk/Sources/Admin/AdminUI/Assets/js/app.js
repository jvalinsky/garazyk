// AT Protocol Admin UI - Client-side interactivity

(function() {
  'use strict';

  // ============================================================================
  // Configuration
  // ============================================================================

  const CONFIG = {
    services: ['pds', 'plc', 'relay', 'appview', 'chat', 'ozone'],
    activeServiceKey: 'adminui_active_service',
    sidebarCollapsePrefix: 'sidebar_collapsed_',
  };

  // ============================================================================
  // Service Switching
  // ============================================================================

  function initServiceSwitching() {
    const serviceSegments = document.querySelectorAll('.service-segment');
    const sidebar = document.getElementById('sidebar');
    const contentPane = document.getElementById('content-pane');

    serviceSegments.forEach((segment) => {
      segment.addEventListener('click', (e) => {
        e.preventDefault();
        const service = segment.dataset.service;
        switchToService(service);
      });
    });

    // Restore previously selected service
    const savedService = localStorage.getItem(CONFIG.activeServiceKey) || 'pds';
    switchToService(savedService);
  }

  function switchToService(service) {
    if (!CONFIG.services.includes(service)) return;

    // Update service segments
    document.querySelectorAll('.service-segment').forEach((seg) => {
      seg.classList.remove('active');
      seg.setAttribute('aria-selected', 'false');
    });
    document.querySelector(`.service-segment[data-service="${service}"]`).classList.add('active');
    document.querySelector(`.service-segment[data-service="${service}"]`).setAttribute('aria-selected', 'true');

    // Show/hide sidebar sections
    document.querySelectorAll('.sidebar-section').forEach((section) => {
      const sectionService = section.dataset.service;
      if (sectionService === service) {
        section.style.display = 'block';
      } else {
        section.style.display = 'none';
      }
    });

    // Save preference
    localStorage.setItem(CONFIG.activeServiceKey, service);
  }

  // ============================================================================
  // Sidebar Section Collapse/Expand
  // ============================================================================

  function initSidebarSections() {
    const sectionTitles = document.querySelectorAll('.sidebar-section-title');

    sectionTitles.forEach((title) => {
      title.addEventListener('click', (e) => {
        e.preventDefault();
        const controlsId = title.getAttribute('aria-controls');
        const itemsDiv = document.getElementById(controlsId);
        const isExpanded = title.getAttribute('aria-expanded') === 'true';

        if (itemsDiv) {
          if (isExpanded) {
            itemsDiv.classList.add('hidden');
            title.setAttribute('aria-expanded', 'false');
            localStorage.setItem(CONFIG.sidebarCollapsePrefix + controlsId, 'true');
          } else {
            itemsDiv.classList.remove('hidden');
            title.setAttribute('aria-expanded', 'true');
            localStorage.removeItem(CONFIG.sidebarCollapsePrefix + controlsId);
          }
        }
      });
    });

    // Restore collapse state
    document.querySelectorAll('.sidebar-items').forEach((items) => {
      const id = items.id;
      if (localStorage.getItem(CONFIG.sidebarCollapsePrefix + id)) {
        items.classList.add('hidden');
        const title = document.querySelector(`[aria-controls="${id}"]`);
        if (title) {
          title.setAttribute('aria-expanded', 'false');
        }
      }
    });
  }

  // ============================================================================
  // Navigation Toggle
  // ============================================================================

  function initNavToggle() {
    const navToggle = document.getElementById('nav-toggle');
    const sidebar = document.querySelector('aside[role="complementary"]');

    if (navToggle) {
      navToggle.addEventListener('click', (e) => {
        e.preventDefault();
        sidebar.classList.toggle('hidden');
      });
    }
  }

  // ============================================================================
  // Sidebar Active State
  // ============================================================================

  function initSidebarActive() {
    const sidebarItems = document.querySelectorAll('.sidebar-item');

    sidebarItems.forEach((item) => {
      item.addEventListener('click', function() {
        // Remove active from all items in same group
        const parent = this.closest('.sidebar-items');
        if (parent) {
          parent.querySelectorAll('.sidebar-item').forEach((i) => {
            i.classList.remove('active');
          });
        }
        this.classList.add('active');
      });

      // Auto-activate based on URL
      const href = item.getAttribute('hx-push-url');
      if (href && window.location.pathname === href) {
        item.classList.add('active');
      }
    });
  }

  // ============================================================================
  // HTMX Event Handlers
  // ============================================================================

  function initHTMXHandlers() {
    // Show loading indicator before request
    document.body.addEventListener('htmx:beforeRequest', function(evt) {
      const target = document.querySelector(evt.detail.target);
      if (target) {
        const spinner = document.createElement('div');
        spinner.className = 'loading-indicator';
        target.parentElement.appendChild(spinner);
      }
    });

    // Hide loading indicator after request
    document.body.addEventListener('htmx:afterRequest', function(evt) {
      const spinner = document.querySelector('.loading-indicator');
      if (spinner) {
        spinner.remove();
      }
    });

    // Initialize new content after swap
    document.body.addEventListener('htmx:afterSwap', function(evt) {
      // Re-bind event handlers for newly loaded content
      initSidebarActive();
    });

    // Handle errors
    document.body.addEventListener('htmx:responseError', function(evt) {
      showErrorNotification(`Error: ${evt.detail.xhr.status} ${evt.detail.xhr.statusText}`);
    });

    // Handle network errors
    document.body.addEventListener('htmx:sendError', function(evt) {
      showErrorNotification('Network error: Could not reach server');
    });
  }

  // ============================================================================
  // Notifications
  // ============================================================================

  function showErrorNotification(message) {
    const alert = document.createElement('div');
    alert.className = 'alert alert-destructive';
    alert.innerHTML = `
      <span>${message}</span>
      <button onclick="this.parentElement.remove()" aria-label="Close" style="background: none; border: none; color: inherit; cursor: pointer; font-weight: bold;">×</button>
    `;

    const contentPane = document.getElementById('content-pane');
    if (contentPane) {
      contentPane.insertBefore(alert, contentPane.firstChild);
      setTimeout(() => alert.remove(), 5000);
    }
  }

  function showSuccessNotification(message) {
    const alert = document.createElement('div');
    alert.className = 'alert alert-success';
    alert.innerHTML = `
      <span>${message}</span>
      <button onclick="this.parentElement.remove()" aria-label="Close" style="background: none; border: none; color: inherit; cursor: pointer; font-weight: bold;">×</button>
    `;

    const contentPane = document.getElementById('content-pane');
    if (contentPane) {
      contentPane.insertBefore(alert, contentPane.firstChild);
      setTimeout(() => alert.remove(), 3000);
    }
  }

  // ============================================================================
  // Keyboard Navigation
  // ============================================================================

  function initKeyboardNavigation() {
    document.addEventListener('keydown', function(evt) {
      // Command/Ctrl + Number to switch services
      if ((evt.metaKey || evt.ctrlKey) && !evt.shiftKey && !evt.altKey) {
        const num = parseInt(evt.key);
        if (num >= 1 && num <= CONFIG.services.length) {
          evt.preventDefault();
          switchToService(CONFIG.services[num - 1]);
        }
      }

      // Cmd/Ctrl+F to focus search (if available)
      if ((evt.metaKey || evt.ctrlKey) && evt.key === 'f') {
        const searchInput = document.querySelector('input[type="search"], input[placeholder*="search" i]');
        if (searchInput) {
          evt.preventDefault();
          searchInput.focus();
        }
      }
    });
  }

  // ============================================================================
  // Status Bar Updates
  // ============================================================================

  function initStatusBar() {
    updateLastSync();
    setInterval(updateLastSync, 60000); // Update every minute
  }

  function updateLastSync() {
    const lastSyncEl = document.getElementById('last-sync');
    if (lastSyncEl) {
      const now = new Date();
      lastSyncEl.textContent = now.toLocaleTimeString();
    }
  }

  // ============================================================================
  // Form Handling
  // ============================================================================

  function initFormHandlers() {
    // Auto-trim whitespace on form inputs
    document.addEventListener('htmx:afterSwap', function() {
      document.querySelectorAll('.form-input').forEach((input) => {
        input.addEventListener('blur', function() {
          this.value = this.value.trim();
        });
      });
    });

    // Handle form submissions with validation
    document.addEventListener('submit', function(evt) {
      const form = evt.target;
      if (form.classList.contains('form')) {
        // Add client-side validation if needed
        const requiredInputs = form.querySelectorAll('[required]');
        let valid = true;

        requiredInputs.forEach((input) => {
          if (!input.value.trim()) {
            valid = false;
            input.focus();
          }
        });

        if (!valid) {
          evt.preventDefault();
          showErrorNotification('Please fill in all required fields');
        }
      }
    });
  }

  // ============================================================================
  // Table Interactions
  // ============================================================================

  function initTableHandlers() {
    document.addEventListener('htmx:afterSwap', function() {
      // Make table rows clickable if they have data attributes
      document.querySelectorAll('.table tbody tr').forEach((row) => {
        row.style.cursor = 'pointer';
        row.addEventListener('click', function(evt) {
          // Don't trigger if clicking a button
          if (evt.target.closest('button')) return;

          // Look for an action button to trigger
          const actionBtn = this.querySelector('[hx-get], [hx-post], [hx-put], [hx-delete]');
          if (actionBtn) {
            actionBtn.click();
          }
        });
      });
    });
  }

  // ============================================================================
  // Dialog Management
  // ============================================================================

  function initDialogHandlers() {
    document.addEventListener('htmx:afterSwap', function() {
      document.querySelectorAll('dialog').forEach((dialog) => {
        // Close button handling
        const closeBtn = dialog.querySelector('button[type="button"]');
        if (closeBtn) {
          closeBtn.addEventListener('click', () => {
            dialog.close();
          });
        }

        // Close on backdrop click
        dialog.addEventListener('click', (evt) => {
          if (evt.target === dialog) {
            dialog.close();
          }
        });

        // Escape key to close
        dialog.addEventListener('keydown', (evt) => {
          if (evt.key === 'Escape') {
            dialog.close();
          }
        });
      });
    });
  }

  // ============================================================================
  // Debounced Search
  // ============================================================================

  function initSearchHandlers() {
    let searchTimeout;

    document.addEventListener('htmx:beforeRequest', function(evt) {
      const input = evt.detail.xhr.searchParams?.get('q');
      if (input) {
        // Clear previous timeout
        if (searchTimeout) {
          clearTimeout(searchTimeout);
        }
      }
    });
  }

  // ============================================================================
  // Initialization
  // ============================================================================

  document.addEventListener('DOMContentLoaded', function() {
    initServiceSwitching();
    initSidebarSections();
    initNavToggle();
    initSidebarActive();
    initHTMXHandlers();
    initKeyboardNavigation();
    initStatusBar();
    initFormHandlers();
    initTableHandlers();
    initDialogHandlers();
    initSearchHandlers();
  });

  // ============================================================================
  // Global Utilities
  // ============================================================================

  // Export for use in templates
  window.AdminUI = {
    showError: showErrorNotification,
    showSuccess: showSuccessNotification,
    switchService: switchToService,
  };
})();
