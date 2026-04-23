/**
 * Admin Security & Session Management
 */

import { AdminPanel } from './admin-panel.js';

function getConfirm() {
    return window.AdminUI?.confirm || window.confirm;
}

export function init() {
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-action]');
        if (!btn) return;
        
        const action = btn.dataset.action;
        if (action.startsWith('security-')) {
            e.preventDefault();
            handleSecurityAction(btn);
        }
    });
}

async function handleSecurityAction(btn) {
    const action = btn.dataset.action;
    const Conf = getConfirm();
    
    try {
        if (action === 'security-revoke-session') {
            const token = btn.dataset.token;
            Conf.confirm({
                title: 'Revoke Session',
                message: 'Revoke this session? The user will be logged out immediately.',
                confirmLabel: 'Revoke',
                destructive: true,
                onConfirm: async () => {
                    const resp = await fetch('/admin/security/sessions', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + AdminPanel.getToken() },
                        body: JSON.stringify({ action: 'revoke', token })
                    });
                    if (resp.ok) {
                        window.AdminUI.showSuccess('Session revoked');
                        btn.closest('tr').remove();
                    }
                }
            });
        } else if (action === 'security-revoke-all') {
            const did = btn.dataset.did;
            Conf.confirm({
                title: 'Revoke All Sessions',
                message: `Revoke ALL sessions for ${did}? This will force logout on all devices.`,
                confirmLabel: 'Revoke All',
                destructive: true,
                onConfirm: async () => {
                    const resp = await fetch('/admin/security/sessions', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + AdminPanel.getToken() },
                        body: JSON.stringify({ action: 'revokeAll', did })
                    });
                    if (resp.ok) {
                        window.AdminUI.showSuccess('All sessions revoked');
                        document.getElementById('session-list-container').innerHTML = '';
                    }
                }
            });
        } else if (action === 'security-revoke-app-password') {
            const id = btn.dataset.id;
            const did = btn.dataset.did;
            Conf.confirm({
                title: 'Delete App Password',
                message: 'Delete this application password? Any app using it will lose access.',
                confirmLabel: 'Delete',
                destructive: true,
                onConfirm: async () => {
                    const resp = await fetch('/admin/security/app-passwords', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + AdminPanel.getToken() },
                        body: JSON.stringify({ action: 'revoke', id, did })
                    });
                    if (resp.ok) {
                        window.AdminUI.showSuccess('App password deleted');
                        btn.closest('tr').remove();
                    }
                }
            });
        }
    } catch (err) {
        window.AdminUI.showError(err.message);
    }
}

export const AdminSecurity = {
    init
};
