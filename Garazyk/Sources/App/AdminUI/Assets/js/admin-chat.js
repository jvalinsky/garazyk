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

async function handleConvoAction(event) {
    const btn = event.currentTarget;
    const action = btn.dataset.action;
    const convoId = btn.dataset.convoId;
    
    try {
        if (action === 'lock') {
            await AdminPanel.lockConversation(convoId);
            window.AdminUI.showSuccess('Conversation locked');
        } else if (action === 'unlock') {
            await AdminPanel.unlockConversation(convoId);
            window.AdminUI.showSuccess('Conversation unlocked');
        }
        loadConversations();
    } catch (err) {
        window.AdminUI.showError(err.message);
    }
}

export const AdminChat = {
    loadConversations,
    handleConvoAction
};
