// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab Video Panel — upload, job polling, and playback UI.
 */

(function () {
    function initVideoPanel(bridge) {
        const panel = document.getElementById('panel-video');
        const uploadCard = document.getElementById('video-upload');
        const fileInput = document.getElementById('video-file-input');
        const uploadBtn = document.getElementById('video-upload-btn');
        const progressEl = document.getElementById('video-progress');
        const progressFill = document.getElementById('video-progress-fill');
        const progressText = document.getElementById('video-progress-text');
        const jobsEl = document.getElementById('video-jobs');

        if (!panel || !uploadCard || !fileInput || !uploadBtn || !progressEl || !progressFill || !progressText || !jobsEl || !bridge) {
            return null;
        }

        if (panel.__skylabVideoInitialized) {
            return panel.__skylabVideoApi || null;
        }

        const state = {
            jobs: new Map(),
            pollingTimers: new Map(),
            uploadCounter: 0,
            limitsEl: null,
            activeObserver: null,
        };

        panel.__skylabVideoInitialized = true;

        function getErrorMessage(payload, fallback) {
            if (!payload) return fallback;
            if (typeof payload === 'string') return payload || fallback;
            if (typeof payload.message === 'string' && payload.message.trim()) return payload.message;
            if (typeof payload.error === 'string' && payload.error.trim()) return payload.error;
            if (typeof payload.detail === 'string' && payload.detail.trim()) return payload.detail;
            return fallback;
        }

        function normalizeJobState(value) {
            const raw = String(value || 'pending').trim();
            const upper = raw.toUpperCase();

            if (upper.includes('COMPLETE')) return 'completed';
            if (upper.includes('FAIL')) return 'failed';
            if (upper.includes('PROCESS') || upper.includes('RUN') || upper.includes('UPLOAD') || upper.includes('QUEUE')) {
                return 'processing';
            }
            if (upper.includes('PENDING') || upper.includes('WAIT')) return 'pending';

            return raw.toLowerCase().replace(/[^a-z0-9_-]+/g, '-');
        }

        function labelizeState(state) {
            return String(state || 'pending').replace(/[-_]+/g, ' ').trim().toUpperCase();
        }

        function toPercent(value, stateClass) {
            if (typeof value === 'number' && Number.isFinite(value)) {
                if (value <= 1 && value > 0) {
                    return Math.max(0, Math.min(100, Math.round(value * 100)));
                }
                return Math.max(0, Math.min(100, Math.round(value)));
            }

            if (stateClass === 'completed') return 100;
            if (stateClass === 'pending') return 0;
            return null;
        }

        function extractJobId(payload) {
            if (!payload || typeof payload !== 'object') return null;

            return payload.jobId ||
                payload.job?.jobId ||
                payload.id ||
                payload.job?.id ||
                payload.uri ||
                payload.job?.uri ||
                null;
        }

        function extractBlobUrl(payload) {
            if (!payload) return null;
            if (typeof payload === 'string') {
                if (/^(blob:|https?:|\/)/i.test(payload)) return payload;
                return null;
            }

            const candidates = [
                payload.blobUrl,
                payload.videoUrl,
                payload.playbackUrl,
                payload.url,
                payload.href,
                payload.blob?.url,
                payload.blob?.href,
                payload.blob?.ref?.$link,
                payload.blob?.ref?.link,
                payload.playback?.url,
                payload.media?.url,
            ];

            for (const candidate of candidates) {
                if (typeof candidate === 'string' && /^(blob:|https?:|\/)/i.test(candidate)) {
                    return candidate;
                }
            }

            return null;
        }

        function normalizeJob(payload, fallbackJobId = null) {
            const data = payload?.job && typeof payload.job === 'object'
                ? payload.job
                : (payload && typeof payload === 'object' ? payload : {});
            const jobId = extractJobId(data) || fallbackJobId;
            const stateClass = normalizeJobState(data.state || data.status || payload?.state || payload?.status);
            const progress = toPercent(
                data.progress ?? data.percent ?? data.completion ?? data.completedPercent ?? payload?.progress ?? payload?.percent,
                stateClass,
            );
            const blobUrl = extractBlobUrl(data) || extractBlobUrl(payload);
            const message = getErrorMessage(data, getErrorMessage(payload, ''));

            return {
                jobId,
                rawState: String(data.state || data.status || payload?.state || payload?.status || 'pending'),
                state: stateClass,
                progress: progress == null ? null : progress,
                blobUrl,
                message: message || null,
            };
        }

        function setProgress(percent, text, visible = true) {
            const clamped = Math.max(0, Math.min(100, Math.round(Number.isFinite(percent) ? percent : 0)));
            progressEl.style.display = visible ? 'block' : 'none';
            progressFill.style.width = `${clamped}%`;
            progressText.textContent = text || `${clamped}%`;
        }

        function resetProgress() {
            progressFill.style.background = 'var(--color-accent)';
            setProgress(0, '0%', false);
        }

        function ensureLimitsElement() {
            if (state.limitsEl) return state.limitsEl;

            const limitsEl = document.createElement('div');
            limitsEl.id = 'video-upload-limits';
            limitsEl.setAttribute('aria-live', 'polite');
            limitsEl.style.marginTop = 'var(--space-sm)';
            limitsEl.style.marginBottom = 'var(--space-sm)';
            limitsEl.style.fontSize = 'var(--font-size-xs)';
            limitsEl.style.color = 'var(--color-text-secondary)';
            limitsEl.textContent = 'Remaining daily uploads: —';

            const titleEl = uploadCard.querySelector('.skylab-card-title');
            if (titleEl && titleEl.parentNode) {
                titleEl.insertAdjacentElement('afterend', limitsEl);
            } else {
                uploadCard.insertBefore(limitsEl, fileInput);
            }

            state.limitsEl = limitsEl;
            return limitsEl;
        }

        function setLimitsText(text) {
            const limitsEl = ensureLimitsElement();
            limitsEl.textContent = text;
        }

        function clearPolling(jobId) {
            const timerId = state.pollingTimers.get(jobId);
            if (timerId) {
                clearTimeout(timerId);
                state.pollingTimers.delete(jobId);
            }
        }

        function upsertJob(update) {
            if (!update || !update.jobId) return null;

            const existing = state.jobs.get(update.jobId) || {};
            const next = {
                ...existing,
                ...update,
                jobId: update.jobId,
                createdAt: existing.createdAt || update.createdAt || Date.now(),
                updatedAt: Date.now(),
            };

            if (!next.state) {
                next.state = 'pending';
            }
            if (next.progress == null) {
                next.progress = toPercent(null, next.state);
            }

            state.jobs.set(update.jobId, next);
            renderJobs();
            return next;
        }

        function renderJobs() {
            jobsEl.innerHTML = '';

            const jobs = Array.from(state.jobs.values()).sort((a, b) => {
                const aTime = a.createdAt || a.updatedAt || 0;
                const bTime = b.createdAt || b.updatedAt || 0;
                return bTime - aTime;
            });

            if (!jobs.length) {
                const empty = document.createElement('div');
                empty.className = 'skylab-empty-state';
                empty.textContent = 'No video jobs';
                jobsEl.appendChild(empty);
                return;
            }

            for (const job of jobs) {
                const card = document.createElement('div');
                card.className = 'skylab-video-job';
                card.dataset.jobId = job.jobId;

                const header = document.createElement('div');
                header.style.display = 'flex';
                header.style.justifyContent = 'space-between';
                header.style.alignItems = 'center';
                header.style.gap = 'var(--space-sm)';

                const idWrap = document.createElement('div');
                idWrap.style.minWidth = '0';

                const idLabel = document.createElement('div');
                idLabel.style.fontSize = 'var(--font-size-xs)';
                idLabel.style.color = 'var(--color-text-tertiary)';
                idLabel.style.marginBottom = '2px';
                idLabel.textContent = 'Job ID';

                const idValue = document.createElement('div');
                idValue.style.fontFamily = 'var(--font-mono)';
                idValue.style.fontSize = 'var(--font-size-sm)';
                idValue.style.wordBreak = 'break-all';
                idValue.textContent = job.jobId || '—';

                idWrap.appendChild(idLabel);
                idWrap.appendChild(idValue);

                const stateBadge = document.createElement('span');
                stateBadge.className = `skylab-video-job-state ${job.state}`;
                stateBadge.textContent = labelizeState(job.state);

                header.appendChild(idWrap);
                header.appendChild(stateBadge);
                card.appendChild(header);

                const progressRow = document.createElement('div');
                progressRow.style.marginTop = 'var(--space-sm)';
                progressRow.style.fontSize = 'var(--font-size-xs)';
                progressRow.style.color = 'var(--color-text-secondary)';

                const progressValue = job.progress == null ? '—' : `${job.progress}%`;
                progressRow.textContent = `Progress: ${progressValue}`;
                card.appendChild(progressRow);

                if (job.message) {
                    const message = document.createElement('div');
                    message.style.marginTop = 'var(--space-sm)';
                    message.style.fontSize = 'var(--font-size-xs)';
                    message.style.color = 'var(--color-text-secondary)';
                    message.textContent = job.message;
                    card.appendChild(message);
                }

                if (job.state === 'completed' && job.blobUrl) {
                    const previewLabel = document.createElement('div');
                    previewLabel.style.marginTop = 'var(--space-sm)';
                    previewLabel.style.fontSize = 'var(--font-size-xs)';
                    previewLabel.style.color = 'var(--color-text-secondary)';
                    previewLabel.textContent = 'Playback';
                    card.appendChild(previewLabel);

                    const video = document.createElement('video');
                    video.controls = true;
                    video.playsInline = true;
                    video.preload = 'metadata';
                    video.src = job.blobUrl;
                    video.style.width = '100%';
                    video.style.marginTop = 'var(--space-xs)';
                    video.style.borderRadius = 'var(--radius-md)';
                    video.style.background = '#000';
                    card.appendChild(video);
                }

                jobsEl.appendChild(card);
            }
        }

        async function refreshUploadLimits() {
            const limitsEl = ensureLimitsElement();

            if (!bridge?.auth) {
                limitsEl.textContent = 'Remaining daily uploads: sign in to view';
                return;
            }

            limitsEl.textContent = 'Remaining daily uploads: loading…';

            try {
                const resp = await bridge.xrpc('app.bsky.video.getUploadLimits', null, null, {
                    service: 'video',
                    auth: true,
                });

                if (!resp.ok) {
                    limitsEl.textContent = `Remaining daily uploads: unavailable (${resp.status || 'error'})`;
                    return;
                }

                const data = resp.data?.limits || resp.data || {};
                const remaining = data.remaining ?? data.remainingDaily ?? data.remainingUploads ?? data.uploadsRemaining ?? data.available ?? null;
                const limit = data.limit ?? data.dailyLimit ?? data.maxUploads ?? data.maxDailyUploads ?? null;
                const used = data.used ?? data.usedDaily ?? data.uploadsUsed ?? data.consumed ?? null;
                const resetAt = data.resetAt || data.resetTime || data.nextResetAt || null;

                let text;
                if (remaining != null) {
                    text = `Remaining daily uploads: ${remaining}`;
                    if (limit != null) {
                        text += ` of ${limit}`;
                    }
                } else if (used != null && limit != null) {
                    const computedRemaining = Math.max(limit - used, 0);
                    text = `Remaining daily uploads: ${computedRemaining} of ${limit}`;
                } else {
                    text = 'Remaining daily uploads: unavailable';
                }

                if (typeof resetAt === 'string' && resetAt.trim()) {
                    text += ` · resets ${resetAt}`;
                }

                limitsEl.textContent = text;
            } catch (error) {
                limitsEl.textContent = `Remaining daily uploads: unavailable (${error.message || 'network error'})`;
            }
        }

        function stopPolling(jobId) {
            clearPolling(jobId);
        }

        async function pollJobStatus(jobId) {
            stopPolling(jobId);

            const tick = async () => {
                try {
                    const resp = await bridge.xrpc('app.bsky.video.getJobStatus', { jobId }, null, {
                        service: 'video',
                        auth: true,
                    });

                    if (resp.ok) {
                        const normalized = normalizeJob(resp.data, jobId);
                        const current = upsertJob(normalized);

                        if (current?.state === 'completed' || current?.state === 'failed') {
                            stopPolling(jobId);
                            return;
                        }
                    }
                } catch (error) {
                    const current = state.jobs.get(jobId);
                    if (current) {
                        upsertJob({
                            ...current,
                            jobId,
                            message: error.message || 'Unable to refresh job status',
                        });
                    }
                }

                const timerId = window.setTimeout(tick, 2000);
                state.pollingTimers.set(jobId, timerId);
            };

            tick();
        }

        async function uploadSelectedFile() {
            const file = fileInput.files?.[0];
            if (!file) {
                setProgress(0, 'Choose a video file first', true);
                return;
            }

            const uploadId = ++state.uploadCounter;
            uploadBtn.disabled = true;
            progressFill.style.background = 'var(--color-accent)';
            setProgress(0, 'Reading file…', true);

            try {
                const arrayBuffer = await file.arrayBuffer();
                const blob = new Blob([arrayBuffer], {
                    type: file.type || 'application/octet-stream',
                });

                setProgress(0, 'Getting service auth…', true);

                const authResp = await bridge.xrpc(
                    'com.atproto.server.getServiceAuth',
                    {
                        aud: 'did:web:localhost',
                        lxm: 'app.bsky.video.uploadVideo',
                    },
                    null,
                    { service: 'pds', auth: true },
                );

                if (!authResp.ok) {
                    throw new Error(getErrorMessage(authResp.data, 'Failed to get service auth token'));
                }

                const serviceToken =
                    authResp.data?.token ||
                    authResp.data?.serviceJwt ||
                    authResp.data?.jwt ||
                    authResp.data?.accessJwt ||
                    null;

                if (!serviceToken) {
                    throw new Error('Service auth token was not returned');
                }

                const videoBaseUrl = bridge.services?.video || (typeof bridge.serviceUrl === 'function' ? bridge.serviceUrl('video') : null);
                if (!videoBaseUrl) {
                    throw new Error('Video service URL is unavailable');
                }

                setProgress(0, 'Uploading…', true);

                const uploadResponse = await new Promise((resolve, reject) => {
                    const xhr = new XMLHttpRequest();
                    xhr.open('POST', `${videoBaseUrl}/xrpc/app.bsky.video.uploadVideo`, true);
                    xhr.responseType = 'text';
                    xhr.setRequestHeader('Authorization', `Bearer ${serviceToken}`);
                    xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream');

                    xhr.upload.onprogress = (event) => {
                        if (!event.lengthComputable) return;
                        const percent = Math.max(0, Math.min(100, Math.round((event.loaded / event.total) * 100)));
                        setProgress(percent, `Uploading… ${percent}%`, true);
                    };

                    xhr.onload = () => {
                        const raw = xhr.responseText || '';
                        let parsed = raw;

                        const contentType = xhr.getResponseHeader('content-type') || '';
                        if (contentType.includes('application/json')) {
                            try {
                                parsed = raw ? JSON.parse(raw) : {};
                            } catch (error) {
                                parsed = raw;
                            }
                        } else {
                            try {
                                parsed = raw ? JSON.parse(raw) : {};
                            } catch (error) {
                                parsed = raw;
                            }
                        }

                        if (xhr.status >= 200 && xhr.status < 300) {
                            resolve({
                                status: xhr.status,
                                data: parsed,
                            });
                        } else {
                            reject(new Error(getErrorMessage(parsed, `Upload failed with HTTP ${xhr.status}`)));
                        }
                    };

                    xhr.onerror = () => reject(new Error('Upload network error'));
                    xhr.onabort = () => reject(new Error('Upload aborted'));
                    xhr.send(blob);
                });

                const normalized = normalizeJob(uploadResponse.data);
                const jobId = normalized.jobId || extractJobId(uploadResponse.data) || null;

                if (jobId) {
                    upsertJob({
                        ...normalized,
                        jobId,
                        state: normalized.state || 'processing',
                        progress: normalized.progress == null ? 0 : normalized.progress,
                    });
                    pollJobStatus(jobId);
                }

                setProgress(100, 'Upload complete', true);
                fileInput.value = '';
                refreshUploadLimits();

                window.setTimeout(() => {
                    if (state.uploadCounter === uploadId) {
                        progressEl.style.display = 'none';
                        progressFill.style.width = '0%';
                        progressText.textContent = '0%';
                    }
                }, 1200);
            } catch (error) {
                progressFill.style.background = 'var(--color-destructive)';
                setProgress(100, `Upload failed: ${error.message || 'unknown error'}`, true);
            } finally {
                uploadBtn.disabled = false;
            }
        }

        function handlePanelActivation() {
            if (panel.classList.contains('active')) {
                refreshUploadLimits();
            }
        }

        uploadBtn.addEventListener('click', uploadSelectedFile);

        state.activeObserver = new MutationObserver(() => {
            handlePanelActivation();
        });
        state.activeObserver.observe(panel, {
            attributes: true,
            attributeFilter: ['class'],
        });

        bridge.on('auth_change', (auth) => {
            if (!auth) {
                for (const jobId of Array.from(state.pollingTimers.keys())) {
                    clearPolling(jobId);
                }
                setLimitsText('Remaining daily uploads: sign in to view');
                return;
            }

            if (panel.classList.contains('active')) {
                refreshUploadLimits();
            }
        });

        renderJobs();
        ensureLimitsElement();
        resetProgress();
        handlePanelActivation();

        panel.__skylabVideoApi = {
            refreshUploadLimits,
            renderJobs,
            upsertJob,
        };

        return panel.__skylabVideoApi;
    }

    if (typeof window !== 'undefined') {
        window.initVideoPanel = initVideoPanel;
    }

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { initVideoPanel };
    }
})();
