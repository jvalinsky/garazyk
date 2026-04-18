/**
 * Admin Ozone Moderation Management
 */

import { AdminPanel } from './admin-panel.js';

export function init() {
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-action]');
        if (!btn) return;
        
        const action = btn.dataset.action;
        if (action.startsWith('ozone-')) {
            handleOzoneAction(e);
        }
    });
}

async function handleOzoneAction(event) {
    const btn = event.currentTarget;
    const action = btn.dataset.action;
    
    try {
        if (action === 'ozone-audit') {
            const did = btn.dataset.did;
            // Navigate to correlations or events filtered by DID
            window.AdminUI.switchService('ozone');
            const correlationsTab = document.querySelector('[hx-push-url="/admin/ozone/correlations"]');
            if (correlationsTab) {
                correlationsTab.click();
                setTimeout(() => {
                    const input = document.querySelector('input[name="did"]');
                    if (input) {
                        input.value = did;
                        input.closest('form').dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
                    }
                }, 100);
            }
        } else if (action === 'ozone-set-delete') {
            const id = btn.dataset.id;
            if (confirm('Delete this moderation set?')) {
                // Implement deleteSet API
                const resp = await fetch('/xrpc/tools.ozone.set.delete', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + AdminPanel.getToken() },
                    body: JSON.stringify({ id })
                });
                if (resp.ok) {
                    window.AdminUI.showSuccess('Set deleted');
                    btn.closest('tr').remove();
                }
            }
        }
    } catch (err) {
        window.AdminUI.showError(err.message);
    }
}

export const AdminOzone = {
    init
};
