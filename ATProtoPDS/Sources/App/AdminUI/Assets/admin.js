/**
 * Admin API helper functions.
 *
 * These utilities are also inlined in the Explore UI (ui.js) for the
 * integrated admin experience. This module exists for standalone admin
 * pages that need the same fetch helpers.
 */

export function getAdminToken() {
    return sessionStorage.getItem('admin_token');
}

export function isAdminAuthenticated() {
    return !!getAdminToken();
}

export function clearAdminSession() {
    sessionStorage.removeItem('admin_token');
}

export async function adminLogin(password) {
    const resp = await fetch('/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
    });
    const data = await resp.json();
    if (resp.ok && data.token) {
        sessionStorage.setItem('admin_token', data.token);
        return data;
    }
    throw new Error(data.error || 'Login failed');
}

export async function adminFetch(url, opts = {}) {
    const token = getAdminToken();
    if (!token) throw new Error('Not admin-authenticated');
    const headers = { ...(opts.headers || {}), 'Authorization': 'Bearer ' + token };
    const resp = await fetch(url, { ...opts, headers });
    if (resp.status === 401) {
        clearAdminSession();
        throw new Error('Admin session expired');
    }
    return resp;
}

export async function getUsers() {
    const resp = await adminFetch('/admin/users');
    return resp.json();
}

export async function getInviteCodes() {
    const resp = await adminFetch('/admin/invites');
    return resp.json();
}

export async function createInviteCode(forAccount, usesAvailable = 1) {
    const resp = await adminFetch('/admin/invites', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ forAccount, usesAvailable })
    });
    return resp.json();
}

export async function disableInviteCode(code) {
    const resp = await adminFetch('/admin/invites/disable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code })
    });
    return resp.json();
}
