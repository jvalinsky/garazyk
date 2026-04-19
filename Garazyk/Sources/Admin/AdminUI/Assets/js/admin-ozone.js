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
            e.preventDefault();
            handleOzoneAction(btn);
        }
    });
}

async function handleOzoneAction(btn) {
    const action = btn.dataset.action;
    
    try {
        if (action === 'ozone-team-add') {
            const email = prompt('Team member email:');
            if (!email) return;
            const role = prompt('Role (admin/mod):', 'mod') || 'mod';
            await ozoneJSON('/xrpc/tools.ozone.team.addMember', { email, role });
            window.AdminUI.showSuccess('Team member added');
            reloadContainer('ozone-team-list-container');
        } else if (action === 'ozone-team-edit') {
            const email = btn.dataset.email;
            if (!email) throw new Error('Missing team member email');
            const role = prompt('New role:', btn.dataset.role || 'mod');
            if (!role) return;
            await ozoneJSON('/xrpc/tools.ozone.team.updateMember', { email, role });
            window.AdminUI.showSuccess('Team member updated');
            reloadContainer('ozone-team-list-container');
        } else if (action === 'ozone-team-delete') {
            const email = btn.dataset.email || btn.dataset.id || btn.dataset.did;
            if (!email) {
                throw new Error('Missing team member identifier');
            }
            if (confirm('Remove this team member?')) {
                await ozoneJSON('/xrpc/tools.ozone.team.deleteMember', { email });
                window.AdminUI.showSuccess('Team member removed');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-set-create') {
            const name = prompt('Set name:');
            if (!name) return;
            const description = prompt('Set description (optional):') || '';
            await ozoneJSON('/xrpc/tools.ozone.set.create', { name, description });
            window.AdminUI.showSuccess('Set created');
            reloadContainer('ozone-sets-list-container');
        } else if (action === 'ozone-set-edit') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing set id');
            const name = prompt('Updated set name (optional):', btn.dataset.name || '');
            if (name === null) return;
            const valuesCSV = prompt('Comma-separated values to replace (optional):', btn.dataset.values || '');
            if (valuesCSV === null) return;
            await ozoneJSON('/xrpc/tools.ozone.set.update', {
                id,
                name: name || undefined,
                values: valuesFromCSV(valuesCSV)
            });
            window.AdminUI.showSuccess('Set updated');
            reloadContainer('ozone-sets-list-container');
        } else if (action === 'ozone-set-delete') {
            const id = btn.dataset.id;
            if (confirm('Delete this moderation set?')) {
                await ozoneJSON('/xrpc/tools.ozone.set.delete', { id });
                window.AdminUI.showSuccess('Set deleted');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-template-create') {
            const name = prompt('Template name:');
            if (!name) return;
            const contentMarkdown = prompt('Template markdown body:');
            if (!contentMarkdown) return;
            await ozoneJSON('/xrpc/tools.ozone.communication.createTemplate', { name, contentMarkdown });
            window.AdminUI.showSuccess('Template created');
            reloadContainer('ozone-templates-list-container');
        } else if (action === 'ozone-template-edit') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing template id');
            const name = prompt('Template name:', btn.dataset.name || '');
            if (name === null) return;
            const contentMarkdown = prompt('Template markdown body:', btn.dataset.contentMarkdown || '');
            if (contentMarkdown === null) return;
            await ozoneJSON('/xrpc/tools.ozone.communication.updateTemplate', {
                id,
                name: name || undefined,
                contentMarkdown: contentMarkdown || undefined
            });
            window.AdminUI.showSuccess('Template updated');
            reloadContainer('ozone-templates-list-container');
        } else if (action === 'ozone-template-delete') {
            const id = btn.dataset.id;
            if (confirm('Delete this communication template?')) {
                await ozoneJSON('/xrpc/tools.ozone.communication.deleteTemplate', { id });
                window.AdminUI.showSuccess('Template deleted');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-verification-grant') {
            const did = prompt('DID to verify (did:plc:...):');
            if (!did) return;
            await ozoneJSON('/xrpc/tools.ozone.verification.grantVerification', { did });
            window.AdminUI.showSuccess('Verification granted');
            reloadContainer('ozone-verification-list-container');
        } else if (action === 'ozone-verification-revoke') {
            const did = btn.dataset.did || prompt('DID to revoke verification for:');
            if (!did) return;
            if (confirm('Revoke verification for ' + did + '?')) {
                await ozoneJSON('/xrpc/tools.ozone.verification.revokeVerification', { did });
                window.AdminUI.showSuccess('Verification revoked');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-safelink-add') {
            const url = prompt('Rule URL (exact or pattern):');
            if (!url) return;
            const ruleAction = prompt('Action (allow/block/warn):', 'block') || 'block';
            await ozoneJSON('/xrpc/tools.ozone.safelink.addRule', { url, action: ruleAction });
            window.AdminUI.showSuccess('Safe link rule added');
            reloadContainer('ozone-safelinks-list-container');
        } else if (action === 'ozone-safelink-update') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing rule id');
            const url = prompt('Updated URL:', btn.dataset.url || '');
            if (url === null) return;
            const ruleAction = prompt('Updated action:', btn.dataset.ruleAction || 'block');
            if (ruleAction === null) return;
            await ozoneJSON('/xrpc/tools.ozone.safelink.updateRule', {
                id,
                url: url || undefined,
                action: ruleAction || undefined
            });
            window.AdminUI.showSuccess('Safe link rule updated');
            reloadContainer('ozone-safelinks-list-container');
        } else if (action === 'ozone-safelink-remove') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing rule id');
            if (confirm('Remove this safe link rule?')) {
                await ozoneJSON('/xrpc/tools.ozone.safelink.removeRule', { id });
                window.AdminUI.showSuccess('Safe link rule removed');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-scheduled-create') {
            const subject = prompt('Subject DID or URI for moderation action:');
            if (!subject) return;
            const eventAction = prompt('Event action (e.g. takedown):', 'takedown') || 'takedown';
            const reason = prompt('Reason/comment (optional):') || '';
            await ozoneJSON('/xrpc/tools.ozone.moderation.scheduleAction', {
                action: {
                    subject,
                    action: eventAction,
                    comment: reason
                }
            });
            window.AdminUI.showSuccess('Scheduled action created');
            reloadContainer('ozone-scheduled-list-container');
        } else if (action === 'ozone-scheduled-cancel') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing scheduled action id');
            if (confirm('Cancel this scheduled moderation action?')) {
                await ozoneJSON('/xrpc/tools.ozone.moderation.cancelScheduledAction', { id });
                window.AdminUI.showSuccess('Scheduled action canceled');
                btn.closest('tr')?.remove();
            }
        } else if (action === 'ozone-config-update') {
            const configSource = btn.dataset.config || document.getElementById('ozone-config-json')?.textContent || '{}';
            const raw = prompt('Server config JSON:', configSource);
            if (!raw) return;
            let payload;
            try {
                payload = JSON.parse(raw);
            } catch (e) {
                throw new Error('Config must be valid JSON');
            }
            await ozoneJSON('/xrpc/tools.ozone.server.updateConfig', payload);
            window.AdminUI.showSuccess('Ozone config updated');
            reloadContainer('ozone-config-data-container');
        } else if (action === 'ozone-setting-upsert') {
            const key = prompt('Option key:');
            if (!key) return;
            const value = prompt('Option value:');
            if (value === null) return;
            const scope = prompt('Option scope:', 'global') || 'global';
            await ozoneJSON('/xrpc/tools.ozone.setting.upsertOption', { key, value, scope });
            window.AdminUI.showSuccess('Option upserted');
            reloadContainer('ozone-config-data-container');
        } else if (action === 'ozone-setting-remove') {
            const key = btn.dataset.key || prompt('Option key to remove:');
            if (!key) return;
            await ozoneJSON('/xrpc/tools.ozone.setting.removeOptions', { keys: [key] });
            window.AdminUI.showSuccess('Option removed');
            btn.closest('tr')?.remove();
        } else if (action === 'ozone-audit') {
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
        } else {
            window.AdminUI.showError('Action not implemented yet: ' + action);
        }
    } catch (err) {
        window.AdminUI.showError(err.message);
    }
}

async function ozoneJSON(path, payload) {
    const resp = await fetch(path, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + AdminPanel.getToken()
        },
        body: JSON.stringify(payload || {})
    });
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
        throw new Error(data.message || data.error || 'Ozone request failed');
    }
    return data;
}

function valuesFromCSV(csv) {
    if (!csv) return [];
    return csv
        .split(',')
        .map((v) => v.trim())
        .filter((v) => v.length > 0);
}

function reloadContainer(id) {
    const el = document.getElementById(id);
    if (el) {
        el.dispatchEvent(new Event('load'));
    }
}

export const AdminOzone = {
    init
};
