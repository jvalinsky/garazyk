/**
 * Admin Ozone Moderation Management
 */

import { AdminPanel } from './admin-panel.js';

function getSheet() {
  return window.AdminUI?.SheetDialog || window.SheetDialog;
}

function getConfirm() {
  return window.AdminUI?.confirm || window.confirm;
}

function getPrompt() {
  return window.AdminUI?.prompt || window.prompt;
}

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
    const Sheet = getSheet();
    
    try {
        if (action === 'ozone-team-add') {
            const sheet = Sheet.open({
                title: 'Add Team Member',
                fields: [
                    { name: 'email', label: 'Email', type: 'email', required: true, placeholder: 'user@example.com' },
                    { name: 'role', label: 'Role', type: 'select', required: true, options: [
                        { value: 'mod', label: 'Moderator' },
                        { value: 'admin', label: 'Admin' }
                    ]}
                ],
                confirmLabel: 'Add',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.team.addMember', { email: data.email, role: data.role });
                    window.AdminUI.showSuccess('Team member added');
                    reloadContainer('ozone-team-list-container');
                }
            });
        } else if (action === 'ozone-team-edit') {
            const email = btn.dataset.email;
            if (!email) throw new Error('Missing team member email');
            const Sheet = getSheet();
            Sheet.open({
                title: 'Edit Team Member',
                initialValues: { email, role: btn.dataset.role || 'mod' },
                fields: [
                    { name: 'email', label: 'Email', type: 'email', required: true },
                    { name: 'role', label: 'Role', type: 'select', required: true, options: [
                        { value: 'mod', label: 'Moderator' },
                        { value: 'admin', label: 'Admin' }
                    ]}
                ],
                confirmLabel: 'Update',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.team.updateMember', { email: data.email, role: data.role });
                    window.AdminUI.showSuccess('Team member updated');
                    reloadContainer('ozone-team-list-container');
                }
            });
        } else if (action === 'ozone-team-delete') {
            const email = btn.dataset.email || btn.dataset.id || btn.dataset.did;
            if (!email) throw new Error('Missing team member identifier');
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Remove Team Member',
                message: `Remove ${email} from the team?`,
                confirmLabel: 'Remove',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.team.deleteMember', { email });
                    window.AdminUI.showSuccess('Team member removed');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-set-create') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Create Moderation Set',
                fields: [
                    { name: 'name', label: 'Set Name', required: true, placeholder: 'e.g., blocked-words' },
                    { name: 'description', label: 'Description', type: 'textarea', placeholder: 'Optional description' }
                ],
                confirmLabel: 'Create',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.set.create', { name: data.name, description: data.description || '' });
                    window.AdminUI.showSuccess('Set created');
                    reloadContainer('ozone-sets-list-container');
                }
            });
        } else if (action === 'ozone-set-edit') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing set id');
            const Sheet = getSheet();
            Sheet.open({
                title: 'Edit Moderation Set',
                initialValues: { name: btn.dataset.name || '', values: btn.dataset.values || '' },
                fields: [
                    { name: 'name', label: 'Set Name', placeholder: 'e.g., blocked-words' },
                    { name: 'values', label: 'Values (comma-separated)', type: 'textarea', placeholder: 'word1, word2, word3' }
                ],
                confirmLabel: 'Update',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.set.update', {
                        id,
                        name: data.name || undefined,
                        values: valuesFromCSV(data.values)
                    });
                    window.AdminUI.showSuccess('Set updated');
                    reloadContainer('ozone-sets-list-container');
                }
            });
        } else if (action === 'ozone-set-delete') {
            const id = btn.dataset.id;
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Delete Set',
                message: 'Delete this moderation set? This action cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.set.delete', { id });
                    window.AdminUI.showSuccess('Set deleted');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-template-create') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Create Communication Template',
                fields: [
                    { name: 'name', label: 'Template Name', required: true, placeholder: 'e.g., welcome-message' },
                    { name: 'contentMarkdown', label: 'Template Body', type: 'textarea', required: true, rows: 6, placeholder: 'Markdown content...' }
                ],
                confirmLabel: 'Create',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.communication.createTemplate', { name: data.name, contentMarkdown: data.contentMarkdown });
                    window.AdminUI.showSuccess('Template created');
                    reloadContainer('ozone-templates-list-container');
                }
            });
        } else if (action === 'ozone-template-edit') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing template id');
            const Sheet = getSheet();
            Sheet.open({
                title: 'Edit Communication Template',
                initialValues: { name: btn.dataset.name || '', contentMarkdown: btn.dataset.contentMarkdown || '' },
                fields: [
                    { name: 'name', label: 'Template Name', required: true },
                    { name: 'contentMarkdown', label: 'Template Body', type: 'textarea', required: true, rows: 6 }
                ],
                confirmLabel: 'Update',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.communication.updateTemplate', {
                        id,
                        name: data.name || undefined,
                        contentMarkdown: data.contentMarkdown || undefined
                    });
                    window.AdminUI.showSuccess('Template updated');
                    reloadContainer('ozone-templates-list-container');
                }
            });
        } else if (action === 'ozone-template-delete') {
            const id = btn.dataset.id;
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Delete Template',
                message: 'Delete this communication template?',
                confirmLabel: 'Delete',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.communication.deleteTemplate', { id });
                    window.AdminUI.showSuccess('Template deleted');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-verification-grant') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Grant Verification',
                fields: [
                    { name: 'did', label: 'DID', required: true, placeholder: 'did:plc:...' }
                ],
                confirmLabel: 'Grant',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.verification.grantVerification', { did: data.did });
                    window.AdminUI.showSuccess('Verification granted');
                    reloadContainer('ozone-verification-list-container');
                }
            });
        } else if (action === 'ozone-verification-revoke') {
            const did = btn.dataset.did;
            if (!did) throw new Error('Missing DID');
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Revoke Verification',
                message: `Revoke verification for ${did}?`,
                confirmLabel: 'Revoke',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.verification.revokeVerification', { did });
                    window.AdminUI.showSuccess('Verification revoked');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-safelink-add') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Add Safe Link Rule',
                fields: [
                    { name: 'url', label: 'URL (exact or pattern)', required: true, placeholder: 'https://example.com/*' },
                    { name: 'action', label: 'Action', type: 'select', required: true, options: [
                        { value: 'block', label: 'Block' },
                        { value: 'warn', label: 'Warn' },
                        { value: 'allow', label: 'Allow' }
                    ]}
                ],
                confirmLabel: 'Add',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.safelink.addRule', { url: data.url, action: data.action });
                    window.AdminUI.showSuccess('Safe link rule added');
                    reloadContainer('ozone-safelinks-list-container');
                }
            });
        } else if (action === 'ozone-safelink-update') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing rule id');
            const Sheet = getSheet();
            Sheet.open({
                title: 'Edit Safe Link Rule',
                initialValues: { url: btn.dataset.url || '', ruleAction: btn.dataset.ruleAction || 'block' },
                fields: [
                    { name: 'url', label: 'URL', required: true },
                    { name: 'ruleAction', label: 'Action', type: 'select', required: true, options: [
                        { value: 'block', label: 'Block' },
                        { value: 'warn', label: 'Warn' },
                        { value: 'allow', label: 'Allow' }
                    ]}
                ],
                confirmLabel: 'Update',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.safelink.updateRule', {
                        id,
                        url: data.url || undefined,
                        action: data.ruleAction || undefined
                    });
                    window.AdminUI.showSuccess('Safe link rule updated');
                    reloadContainer('ozone-safelinks-list-container');
                }
            });
        } else if (action === 'ozone-safelink-remove') {
            const id = btn.dataset.id;
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Remove Rule',
                message: 'Remove this safe link rule?',
                confirmLabel: 'Remove',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.safelink.removeRule', { id });
                    window.AdminUI.showSuccess('Safe link rule removed');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-scheduled-create') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Schedule Moderation Action',
                fields: [
                    { name: 'subject', label: 'Subject (DID or URI)', required: true, placeholder: 'did:plc:...' },
                    { name: 'action', label: 'Action', type: 'select', required: true, options: [
                        { value: 'takedown', label: 'Takedown' },
                        { value: 'flag', label: 'Flag' },
                        { value: 'ack', label: 'Acknowledge' },
                        { value: 'sbom', label: 'Suspend' }
                    ]},
                    { name: 'comment', label: 'Reason/Comment', type: 'textarea', placeholder: 'Optional reason for this action' }
                ],
                confirmLabel: 'Schedule',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.moderation.scheduleAction', {
                        action: {
                            subject: data.subject,
                            action: data.action,
                            comment: data.comment || ''
                        }
                    });
                    window.AdminUI.showSuccess('Scheduled action created');
                    reloadContainer('ozone-scheduled-list-container');
                }
            });
        } else if (action === 'ozone-scheduled-cancel') {
            const id = btn.dataset.id;
            if (!id) throw new Error('Missing scheduled action id');
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Cancel Action',
                message: 'Cancel this scheduled moderation action?',
                confirmLabel: 'Cancel',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.moderation.cancelScheduledAction', { id });
                    window.AdminUI.showSuccess('Scheduled action canceled');
                    btn.closest('tr')?.remove();
                }
            });
        } else if (action === 'ozone-config-update') {
            const configSource = btn.dataset.config || document.getElementById('ozone-config-json')?.textContent || '{}';
            const Sheet = getSheet();
            Sheet.open({
                title: 'Update Server Config',
                initialValues: { config: configSource },
                fields: [
                    { name: 'config', label: 'JSON Config', type: 'textarea', required: true, rows: 10, placeholder: '{"key": "value"}' }
                ],
                confirmLabel: 'Update',
                onConfirm: async (data) => {
                    let payload;
                    try {
                        payload = JSON.parse(data.config);
                    } catch (e) {
                        throw new Error('Config must be valid JSON');
                    }
                    await ozoneJSON('/xrpc/tools.ozone.server.updateConfig', payload);
                    window.AdminUI.showSuccess('Ozone config updated');
                    reloadContainer('ozone-config-data-container');
                }
            });
        } else if (action === 'ozone-setting-upsert') {
            const Sheet = getSheet();
            Sheet.open({
                title: 'Upsert Setting',
                fields: [
                    { name: 'key', label: 'Option Key', required: true, placeholder: 'setting-name' },
                    { name: 'value', label: 'Option Value', required: true, placeholder: 'setting-value' },
                    { name: 'scope', label: 'Scope', type: 'select', required: true, options: [
                        { value: 'global', label: 'Global' },
                        { value: 'server', label: 'Server' },
                        { value: 'account', label: 'Account' }
                    ]}
                ],
                confirmLabel: 'Save',
                onConfirm: async (data) => {
                    await ozoneJSON('/xrpc/tools.ozone.setting.upsertOption', { key: data.key, value: data.value, scope: data.scope });
                    window.AdminUI.showSuccess('Setting saved');
                    reloadContainer('ozone-config-data-container');
                }
            });
        } else if (action === 'ozone-setting-remove') {
            const key = btn.dataset.key;
            if (!key) throw new Error('Missing option key');
            const Conf = getConfirm();
            Conf.confirm({
                title: 'Remove Setting',
                message: `Remove setting "${key}"?`,
                confirmLabel: 'Remove',
                destructive: true,
                onConfirm: async () => {
                    await ozoneJSON('/xrpc/tools.ozone.setting.removeOptions', { keys: [key] });
                    window.AdminUI.showSuccess('Setting removed');
                    btn.closest('tr')?.remove();
                }
            });
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
