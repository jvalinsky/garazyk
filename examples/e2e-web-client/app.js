/**
 * Garazyk E2E Test Client Logic
 * Designed for programmatic control via window.GarazykE2E
 */

const GarazykE2E = {
    config: {
        pds: "http://localhost:2583",
        appview: "http://localhost:3200",
        chat: "http://localhost:2585",
        germ: "http://localhost:8082"
    },
    session: null,

    /**
     * Initialize configuration from URL parameters
     */
    init() {
        const params = new URLSearchParams(window.location.search);
        if (params.has('pds')) this.config.pds = params.get('pds');
        if (params.has('appview')) this.config.appview = params.get('appview');
        if (params.has('chat')) this.config.chat = params.get('chat');
        if (params.has('germ')) this.config.germ = params.get('germ');

        document.getElementById('url-pds').innerText = this.config.pds;
        document.getElementById('url-appview').innerText = this.config.appview;
        document.getElementById('url-chat').innerText = this.config.chat;
        document.getElementById('url-germ').innerText = this.config.germ;

        console.log("GarazykE2E initialized with config:", this.config);
    },

    /**
     * Authenticate with the PDS
     */
    async login(handle, password) {
        console.log(`Attempting login for ${handle}...`);
        try {
            const resp = await fetch(`${this.config.pds}/xrpc/com.atproto.server.createSession`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ identifier: handle, password: password })
            });

            if (!resp.ok) throw new Error(`Login failed: ${resp.status}`);

            this.session = await resp.json();
            console.log("Login successful:", this.session.did);

            this.updateUIForLogin();
            return this.session;
        } catch (err) {
            console.error(err);
            alert(err.message);
            throw err;
        }
    },

    updateUIForLogin() {
        const badge = document.getElementById('auth-status');
        badge.innerText = `Logged in as ${this.session.handle}`;
        badge.classList.add('logged-in');

        document.getElementById('login-section').classList.add('hidden');
        document.getElementById('timeline-section').classList.remove('hidden');
        document.getElementById('chat-section').classList.remove('hidden');
        document.getElementById('video-section').classList.remove('hidden');
        
        this.loadTimeline();
    },

    /**
     * Fetch timeline from AppView
     */
    async loadTimeline() {
        if (!this.session) return;
        console.log("Loading timeline from AppView...");
        try {
            const resp = await fetch(`${this.config.appview}/xrpc/app.bsky.feed.getTimeline`, {
                headers: { 'Authorization': `Bearer ${this.session.accessJwt}` }
            });
            const data = await resp.json();
            this.renderTimeline(data.feed || []);
        } catch (err) {
            console.error("Failed to load timeline:", err);
        }
    },

    renderTimeline(feed) {
        const container = document.getElementById('timeline-feed');
        container.innerHTML = '';
        feed.forEach(item => {
            const post = item.post;
            const card = document.createElement('div');
            card.className = 'post-card';
            card.innerHTML = `
                <div class="post-author">${post.author.handle}</div>
                <div class="post-text">${post.record.text}</div>
            `;
            container.appendChild(card);
        });
    },

    /**
     * Send a standard plaintext DM via Chat Service
     */
    async sendDM(recipientDid, text) {
        if (!this.session) return;
        console.log(`Sending plaintext DM to ${recipientDid}...`);
        try {
            // 1. Get or create conversation
            const convoResp = await fetch(`${this.config.chat}/xrpc/chat.bsky.convo.getConvoForMembers?members=${recipientDid}`, {
                headers: { 'Authorization': `Bearer ${this.session.accessJwt}` }
            });
            const convoData = await convoResp.json();
            const convoId = convoData.convo.id;

            // 2. Send message
            const sendResp = await fetch(`${this.config.chat}/xrpc/chat.bsky.convo.sendMessage`, {
                method: 'POST',
                headers: { 
                    'Authorization': `Bearer ${this.session.accessJwt}`,
                    'Content-Type': 'application/json' 
                },
                body: JSON.stringify({
                    convoId: convoId,
                    message: {
                        $type: 'chat.bsky.convo.message',
                        text: text,
                        createdAt: new Date().toISOString()
                    }
                })
            });
            
            const result = await sendResp.json();
            this.appendChatMessage(this.session.handle, text, false);
            return result;
        } catch (err) {
            console.error("Failed to send DM:", err);
        }
    },

    /**
     * Send an E2EE DM via Germ Mailbox Service
     */
    async sendEncryptedDM(recipientDid, text) {
        if (!this.session) return;
        console.log(`Sending Germ E2EE DM to ${recipientDid}...`);
        try {
            // Note: In a real client, this would involve MLS key exchange.
            // For the test harness, we simulate the envelope delivery to the mailbox.
            
            // 1. Get recipient's rendezvous/ephemeral address from Germ
            // (Simplified for harness: just use a known test address or poll)
            
            // 2. Deliver "ciphertext" (simulated)
            const simulatedCiphertext = btoa(`ENCRYPTED:${text}`);
            const deliverResp = await fetch(`${this.config.germ}/xrpc/com.germnetwork.mailbox.deliver`, {
                method: 'POST',
                headers: { 
                    'Authorization': `Bearer ${this.session.accessJwt}`,
                    'Content-Type': 'application/json' 
                },
                body: JSON.stringify({
                    address: `test-address-for-${recipientDid}`,
                    ciphertext: { "$bytes": simulatedCiphertext }
                })
            });

            if (deliverResp.ok) {
                this.appendChatMessage(this.session.handle, `[E2EE] ${text}`, true);
            }
            return await deliverResp.json();
        } catch (err) {
            console.error("Failed to send E2EE DM:", err);
        }
    },

    appendChatMessage(sender, text, isEncrypted) {
        const history = document.getElementById('chat-history');
        const div = document.createElement('div');
        div.className = 'chat-msg' + (isEncrypted ? ' encrypted' : '');
        div.innerText = `${sender}: ${text}`;
        history.appendChild(div);
        history.scrollTop = history.scrollHeight;
    },

    /**
     * Play video via HLS.js
     */
    async playVideo(did, cid) {
        const video = document.getElementById('video-player');
        // Construct the CDN URL (assuming our CDN layout)
        const videoUrl = `${this.config.pds}/blob/${did}/${cid}/playlist.m3u8`;
        
        console.log(`Loading video HLS from ${videoUrl}...`);
        
        if (Hls.isSupported()) {
            const hls = new Hls();
            hls.loadSource(videoUrl);
            hls.attachMedia(video);
            hls.on(Hls.Events.MANIFEST_PARSED, () => {
                video.play();
            });
        } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
            video.src = videoUrl;
            video.addEventListener('loadedmetadata', () => {
                video.play();
            });
        }
    }
};

// Initialize on load
window.GarazykE2E = GarazykE2E;
window.addEventListener('DOMContentLoaded', () => GarazykE2E.init());
