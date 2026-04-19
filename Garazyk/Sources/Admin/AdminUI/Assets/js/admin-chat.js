/**
 * Admin Chat Management
 * 
 * Handles monitoring and management of direct message conversations.
 */

import { AdminPanel } from './admin-panel.js';

let convoList = [];
let selectedConvoId = null;

async function loadConversations() {
    const container = document.getElementById('convo-list-container');
    if (!container) return;
    
    try {
        const data = await AdminPanel.listConversations(50);
        convoList = data.convos || [];
        renderConversations();
    } catch (err) {
        console.error('Failed to load conversations:', err);
    }
}

function renderConversations() {
    // This is mostly handled by HTMX now, but we keep this for JS-driven updates if needed
}

async function handleConvoAction(btn) {
    const action = btn.dataset.action;
    
    try {
        if (action === 'lock') {
            const convoId = btn.dataset.convoId;
            await AdminPanel.lockConversation(convoId);
            window.AdminUI.showSuccess('Conversation locked');
        } else if (action === 'unlock') {
            const convoId = btn.dataset.convoId;
            await AdminPanel.unlockConversation(convoId);
            window.AdminUI.showSuccess('Conversation unlocked');
        } else if (action === 'delete-group') {
            const uri = btn.dataset.uri;
            if (confirm('Are you sure you want to delete this group? This action is IRREVERSIBLE.')) {
                // We need to implement deleteGroup API in admin-panel.js
                await AdminPanel.deleteGroup(uri);
                window.AdminUI.showSuccess('Group deleted');
                document.getElementById('group-list-container')?.dispatchEvent(new Event('load'));
            }
        } else if (action === 'revoke-link') {
            const linkId = btn.dataset.id;
            await AdminPanel.revokeInviteLink(linkId);
            window.AdminUI.showSuccess('Invite link revoked');
            document.getElementById('link-list-container')?.dispatchEvent(new Event('load'));
        } else if (action === 'remove-member') {
            const uri = btn.dataset.group;
            const did = btn.dataset.did;
            if (confirm('Remove ' + did + ' from group?')) {
                await AdminPanel.removeMemberFromGroup(uri, did);
                window.AdminUI.showSuccess('Member removed');
                // Reload detail view
                document.getElementById('content-pane')?.dispatchEvent(new Event('load'));
            }
        } else if (action === 'delete-message') {
            const messageId = btn.dataset.messageId || btn.dataset.altMessageId;
            if (!messageId) {
                throw new Error('Missing message id');
            }
            if (confirm('Delete this message for the admin session?')) {
                await AdminPanel.deleteConversationMessage(messageId);
                window.AdminUI.showSuccess('Message removed');
                btn.closest('.log-entry')?.remove();
            }
        }
        
        if (action === 'lock' || action === 'unlock') {
            loadConversations();
        }
    } catch (err) {
        window.AdminUI.showError(err.message);
    }
}

export function init() {
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-action]');
        if (btn && ['lock', 'unlock', 'delete-group', 'revoke-link', 'remove-member', 'delete-message'].includes(btn.dataset.action)) {
            e.preventDefault();
            handleConvoAction(btn);
        }
    });
}

export const AdminChat = {
    init,
    loadConversations,
    handleConvoAction
};
