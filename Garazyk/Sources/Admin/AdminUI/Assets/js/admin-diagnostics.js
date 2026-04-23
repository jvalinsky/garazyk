/**
 * Admin Diagnostics Module
 * Manages the System Diagnostics Dashboard UI components
 */

// ============================================================================
// Sequencer Health Dashboard
// ============================================================================

const DiagnosticsSequencer = {
  chartInstances: {},
  refreshInterval: null,

  init() {
    this.loadCurrentStats();
    this.loadHistory(24);
    this.startAutoRefresh();
  },

  startAutoRefresh() {
    // Auto-refresh every 30 seconds
    this.refreshInterval = setInterval(() => {
      this.loadCurrentStats();
    }, 30000);
  },

  async loadCurrentStats() {
    try {
      const response = await fetch('/admin/api/diagnostics/sequencer/stats');
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.renderStats(data);
    } catch (error) {
      console.error('Failed to load sequencer stats:', error);
      this.showError('Failed to load sequencer stats');
    }
  },

  async loadHistory(hours) {
    try {
      const response = await fetch(`/admin/api/diagnostics/sequencer/history?hours=${hours}`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.renderCharts(data);
    } catch (error) {
      console.error('Failed to load sequencer history:', error);
      this.showError('Failed to load sequencer history');
    }
  },

  renderStats(data) {
    document.getElementById('currentSeq').textContent = data.currentSeq || '-';
    document.getElementById('eventsPerSecond').textContent = (data.eventsPerSecond || 0).toFixed(2);
    document.getElementById('subscriberCount').textContent = data.subscriberCount || '0';
    document.getElementById('backpressureWarnings').textContent = data.backpressureWarnings || '0';
    document.getElementById('backpressureCritical').textContent = data.backpressureCritical || '0';
    document.getElementById('queueOverflows').textContent = data.queueOverflows || '0';

    // Update health status with color
    const healthEl = document.getElementById('healthStatus');
    if (healthEl) {
      const status = data.healthStatus || 'unknown';
      healthEl.textContent = status.toUpperCase();
      healthEl.className = 'metric-value status-' + status;
    }
  },

  renderCharts(data) {
    const dataPoints = data.dataPoints || [];

    // Events per second chart
    this.renderTimeSeriesChart('eventsPerSecondChart', dataPoints, {
      dataKey: 'eventsPerSecond',
      label: 'Events/Second',
      borderColor: '#3b82f6',
      backgroundColor: 'rgba(59, 130, 246, 0.1)'
    });

    // Subscribers chart
    this.renderTimeSeriesChart('subscribersChart', dataPoints, {
      dataKey: 'subscriberCount',
      label: 'Subscriber Count',
      borderColor: '#10b981',
      backgroundColor: 'rgba(16, 185, 129, 0.1)'
    });
  },

  renderTimeSeriesChart(canvasId, dataPoints, options) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;

    // Destroy existing chart if any
    if (this.chartInstances[canvasId]) {
      this.chartInstances[canvasId].destroy();
    }

    // Format labels as times
    const labels = dataPoints.map(dp => {
      const date = new Date(dp.timestamp * 1000);
      return date.toLocaleTimeString();
    });

    const chartData = {
      labels: labels,
      datasets: [{
        label: options.label,
        data: dataPoints.map(dp => dp[options.dataKey]),
        borderColor: options.borderColor,
        backgroundColor: options.backgroundColor,
        tension: 0.1,
        fill: true
      }]
    };

    try {
      // Only initialize Chart if the library is available
      if (typeof Chart !== 'undefined') {
        this.chartInstances[canvasId] = new Chart(canvas, {
          type: 'line',
          data: chartData,
          options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
              legend: {
                display: true,
                position: 'top'
              }
            },
            scales: {
              y: {
                beginAtZero: true
              }
            }
          }
        });
      }
    } catch (error) {
      console.error('Failed to render chart:', error);
    }
  },

  showError(message) {
    const alertEl = document.createElement('div');
    alertEl.className = 'alert alert-destructive';
    alertEl.textContent = message;
    document.querySelector('.content-header')?.insertAdjacentElement('afterend', alertEl);
  }
};

// ============================================================================
// Blob Audit Dashboard
// ============================================================================

const DiagnosticsBlobs = {
  activeJobs: {},
  pollInterval: null,

  init() {
    this.setupEventListeners();
    this.loadRecentAudits();
  },

  setupEventListeners() {
    const auditForm = document.getElementById('auditForm');
    if (auditForm) {
      auditForm.addEventListener('submit', (e) => this.handleAuditSubmit(e));
    }
  },

  async handleAuditSubmit(e) {
    e.preventDefault();

    const auditType = document.getElementById('auditType').value;
    const dryRun = document.getElementById('dryRun').checked;

    try {
      const response = await fetch('/admin/api/diagnostics/blobs/audit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ auditType, dryRun })
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.startPollingJob(data.jobId);
      this.updateActiveJobs();
    } catch (error) {
      console.error('Failed to start audit:', error);
      this.showError('Failed to start audit job');
    }
  },

  startPollingJob(jobId) {
    this.activeJobs[jobId] = {
      status: 'pending',
      progress: 0
    };

    const pollJob = () => {
      this.pollJobStatus(jobId).then(job => {
        if (job.status === 'running' || job.status === 'pending') {
          setTimeout(pollJob, 2000); // Poll every 2 seconds
        } else {
          this.loadRecentAudits(); // Refresh audit history when complete
        }
      });
    };

    pollJob();
  },

  async pollJobStatus(jobId) {
    try {
      const response = await fetch(`/admin/api/diagnostics/blobs/status?jobId=${jobId}`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const job = await response.json();
      this.activeJobs[jobId] = job;
      this.updateActiveJobs();
      return job;
    } catch (error) {
      console.error('Failed to poll job status:', error);
      return this.activeJobs[jobId] || {};
    }
  },

  updateActiveJobs() {
    const activeAuditsEl = document.getElementById('activeAudits');
    const jobs = Object.values(this.activeJobs).filter(job => job.status === 'running' || job.status === 'pending');

    if (jobs.length === 0) {
      activeAuditsEl.innerHTML = '<p class="text-secondary">No active audits</p>';
      return;
    }

    const html = jobs.map(job => `
      <div class="audit-job mt-md">
        <div class="job-header">
          <span class="job-type">${this.formatAuditType(job.job_type)}</span>
          <span class="badge badge-${job.status}">${job.status}</span>
        </div>
        <div class="progress">
          <div class="progress-bar" data-progress="${(job.progress * 100).toFixed(1)}"></div>
        </div>
        <div class="job-info text-sm mt-sm">
          Progress: ${(job.progress * 100).toFixed(1)}%
        </div>
      </div>
    `).join('');

    activeAuditsEl.innerHTML = html;
    activeAuditsEl.querySelectorAll('.progress-bar[data-progress]').forEach((bar) => {
      const pct = Number.parseFloat(bar.getAttribute('data-progress') || '0');
      bar.style.width = `${Number.isFinite(pct) ? pct : 0}%`;
    });
  },

  async loadRecentAudits() {
    // TODO: Implement fetching recent audits from API
    // For now, this is a placeholder
  },

  formatAuditType(type) {
    const mapping = {
      'orphans': 'Orphan Detection',
      'cid_verify': 'CID Verification',
      'consistency': 'Consistency Check',
      'references': 'Reference Scanning'
    };
    return mapping[type] || type;
  },

  showError(message) {
    const alertEl = document.createElement('div');
    alertEl.className = 'alert alert-destructive';
    alertEl.textContent = message;
    document.querySelector('.content-header')?.insertAdjacentElement('afterend', alertEl);
  }
};

// ============================================================================
// Rate Limit Management
// ============================================================================

const DiagnosticsRateLimits = {
  currentQuery: null,

  init() {
    this.setupEventListeners();
    this.loadTopUsers();
  },

  setupEventListeners() {
    const queryForm = document.getElementById('queryForm');
    if (queryForm) {
      queryForm.addEventListener('submit', (e) => this.handleQuery(e));
    }

    const clearBtn = document.getElementById('clearBtn');
    if (clearBtn) {
      clearBtn.addEventListener('click', () => this.handleClear());
    }

    const tableBody = document.querySelector('#topUsersTable tbody');
    if (tableBody) {
      tableBody.addEventListener('click', (event) => {
        const trigger = event.target.closest('[data-action=\"query-rate-user\"]');
        if (!trigger) return;
        const identifier = trigger.getAttribute('data-identifier') || '';
        const type = trigger.getAttribute('data-type') || 'did';
        this.queryUser(identifier, type);
      });
    }
  },

  async handleQuery(e) {
    e.preventDefault();

    const identifier = document.getElementById('identifier').value;
    const type = document.getElementById('type').value;

    try {
      const response = await fetch('/admin/api/diagnostics/ratelimits/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ identifier, type })
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.currentQuery = { identifier, type, ...data };
      this.renderQueryResults(data);
    } catch (error) {
      console.error('Failed to query rate limit:', error);
      this.showError('Failed to query rate limit');
    }
  },

  renderQueryResults(data) {
    const resultsEl = document.getElementById('queryResults');
    resultsEl?.classList.remove('is-hidden', 'hidden');

    document.getElementById('currentCount').textContent = data.currentCount || '0';
    document.getElementById('limit').textContent = data.limit || '-';
    document.getElementById('remaining').textContent = data.remaining || '-';

    const resetSeconds = data.windowEnd ? new Date(data.windowEnd) : null;
    if (resetSeconds) {
      document.getElementById('resetTime').textContent = resetSeconds.toLocaleTimeString();
    }

    // Show clear button only if there's usage
    const clearBtn = document.getElementById('clearBtn');
    if (clearBtn) {
      const shouldHide = !(data.currentCount > 0);
      clearBtn.classList.toggle('is-hidden', shouldHide);
      clearBtn.classList.toggle('hidden', shouldHide);
    }
  },

  async handleClear() {
    if (!this.currentQuery) return;

    const Sheet = window.AdminUI?.SheetDialog || window.SheetDialog;
    if (!Sheet) {
      this.showError('Sheet dialog not available');
      return;
    }

    Sheet.prompt({
      title: 'Clear Rate Limit',
      label: 'Reason for clearing rate limit:',
      initialValue: '',
      placeholder: 'Enter reason...',
      confirmLabel: 'Clear',
      onConfirm: async (reason) => {
        if (!reason) return;
        await this.performClear(reason);
      }
    });
  },

  async performClear(reason) {
    try {
      const response = await fetch('/admin/api/diagnostics/ratelimits/clear', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          identifier: this.currentQuery.identifier,
          type: this.currentQuery.type,
          reason: reason,
          adminDid: 'did:plc:admin'
        })
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const result = await response.json();
      if (result.success) {
        if (window.AdminUI && typeof window.AdminUI.showSuccess === 'function') {
          window.AdminUI.showSuccess('Rate limit cleared successfully.');
        }
        this.handleQuery(new Event('submit'));
      } else {
        this.showError('Failed to clear rate limit: ' + (result.error || 'Unknown error'));
      }
    } catch (error) {
      console.error('Failed to clear rate limit:', error);
      this.showError('Failed to clear rate limit');
    }
  },

  async loadTopUsers() {
    try {
      const response = await fetch('/admin/api/diagnostics/ratelimits/top?limit=20');
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.renderTopUsers(data.users || []);
    } catch (error) {
      console.error('Failed to load top users:', error);
    }
  },

  renderTopUsers(users) {
    const tableBody = document.querySelector('#topUsersTable tbody');
    if (!tableBody) return;

    if (users.length === 0) {
      tableBody.innerHTML = '<tr><td colspan="6" class="text-secondary">No rate limits active</td></tr>';
      return;
    }

      const rows = users.map(user => {
      const percentage = ((user.count / user.limit) * 100).toFixed(1);
      const statusClass = user.status === 'exceeded' ? 'danger' : 'warning';
      const identifier = this.escapeAttr(user.identifier);
      const type = this.escapeAttr(user.type);

      return `
        <tr>
          <td class="monospace">${this.truncate(user.identifier, 30)}</td>
          <td>${user.type}</td>
          <td>${user.count}</td>
          <td>${percentage}%</td>
          <td><span class="badge badge-${statusClass}">${user.status}</span></td>
          <td>
            <button class="btn btn-sm btn-danger" data-action="query-rate-user" data-identifier="${identifier}" data-type="${type}">
              View
            </button>
          </td>
        </tr>
      `;
    }).join('');

    tableBody.innerHTML = rows;
  },

  queryUser(identifier, type) {
    document.getElementById('identifier').value = identifier;
    document.getElementById('type').value = type;
    const form = document.getElementById('queryForm');
    form.dispatchEvent(new Event('submit'));
  },

  truncate(str, length) {
    return str.length > length ? str.substring(0, length) + '...' : str;
  },

  escapeAttr(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#039;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  },

  showError(message) {
    const alertEl = document.createElement('div');
    alertEl.className = 'alert alert-destructive';
    alertEl.textContent = message;
    document.querySelector('.content-header')?.insertAdjacentElement('afterend', alertEl);
  }
};

// ============================================================================
// Initialize on page load
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
  // Auto-detect which module to initialize based on current path
  const path = window.location.pathname;

  if (path.includes('/diagnostics/sequencer')) {
    DiagnosticsSequencer.init();
  } else if (path.includes('/diagnostics/blobs')) {
    DiagnosticsBlobs.init();
  } else if (path.includes('/diagnostics/ratelimits')) {
    DiagnosticsRateLimits.init();
  }
});

window.DiagnosticsSequencer = DiagnosticsSequencer;
window.DiagnosticsBlobs = DiagnosticsBlobs;
window.DiagnosticsRateLimits = DiagnosticsRateLimits;
