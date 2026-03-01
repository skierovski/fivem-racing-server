(() => {
    'use strict';

    const hud = document.getElementById('hud');
    const speedValue = document.getElementById('speedValue');
    const gearValue = document.getElementById('gearValue');
    const rpmFill = document.getElementById('rpmFill');
    const tierLetter = document.getElementById('hudTierLetter');

    const chatMessages = document.getElementById('chatMessages');
    const chatInputWrap = document.getElementById('chatInputWrap');
    const chatInput = document.getElementById('chatInput');

    const MAX_VISIBLE_MESSAGES = 20;
    const FADE_AFTER_MS = 8000;

    const tierLetters = {
        bronze: 'B', silver: 'S', gold: 'G',
        platinum: 'P', diamond: 'D', blacklist: 'X'
    };

    let chatOpen = false;

    window.addEventListener('message', (event) => {
        const data = event.data;

        switch (data.action) {
            case 'showHud':
                hud.classList.toggle('hidden', !data.show);
                break;

            case 'updateHud':
                if (data.inVehicle) {
                    speedValue.textContent = data.speed || 0;
                    gearValue.textContent = data.gear === 0 ? 'R' : data.gear || 'N';
                    const rpmPct = Math.min((data.rpm || 0) * 100, 100);
                    rpmFill.style.width = rpmPct + '%';
                    rpmFill.classList.toggle('redline', rpmPct > 85);
                } else {
                    speedValue.textContent = '0';
                    gearValue.textContent = 'N';
                    rpmFill.style.width = '0%';
                    rpmFill.classList.remove('redline');
                }
                break;

            case 'updateTier':
                if (data.tier) {
                    tierLetter.textContent = tierLetters[data.tier] || 'B';
                    tierLetter.className = 'hud-tier-letter ' + data.tier;
                }
                break;

            case 'chatMessage':
                addChatMessage(data.message);
                break;

            case 'openChat':
                openChatInput();
                break;

            case 'closeChat':
                closeChatInput();
                break;
        }
    });

    function addChatMessage(msg) {
        if (!msg) return;

        const el = document.createElement('div');
        el.classList.add('chat-msg');

        const badge = document.createElement('span');
        badge.classList.add('chat-msg-badge', msg.tier || 'bronze');
        badge.textContent = tierLetters[msg.tier || 'bronze'];

        const name = document.createElement('span');
        name.classList.add('chat-msg-name');
        name.textContent = msg.name || 'Unknown';

        const text = document.createElement('span');
        text.classList.add('chat-msg-text');
        text.textContent = msg.message || '';

        el.appendChild(badge);
        el.appendChild(name);
        el.appendChild(text);
        chatMessages.appendChild(el);

        // Remove old messages
        while (chatMessages.children.length > MAX_VISIBLE_MESSAGES) {
            chatMessages.removeChild(chatMessages.firstChild);
        }

        // Auto-scroll
        chatMessages.scrollTop = chatMessages.scrollHeight;

        // Fade out after delay (unless chat input is open)
        scheduleFade(el);
    }

    function scheduleFade(el) {
        setTimeout(() => {
            if (!chatOpen) {
                el.classList.add('fading');
                setTimeout(() => {
                    if (el.parentNode) el.parentNode.removeChild(el);
                }, 600);
            } else {
                scheduleFade(el);
            }
        }, FADE_AFTER_MS);
    }

    function openChatInput() {
        chatOpen = true;
        chatInputWrap.classList.remove('hidden');
        chatInputWrap.classList.add('active');
        chatInput.value = '';
        chatInput.focus();

        // Show all existing faded messages again
        chatMessages.querySelectorAll('.chat-msg').forEach(m => m.classList.remove('fading'));
    }

    function closeChatInput() {
        chatOpen = false;
        chatInputWrap.classList.add('hidden');
        chatInputWrap.classList.remove('active');
        chatInput.blur();
        fetch('https://hud/closeChat', { method: 'POST', body: '{}' });
    }

    chatInput.addEventListener('keydown', (e) => {
        e.stopPropagation();

        if (e.key === 'Enter') {
            const msg = chatInput.value.trim();
            if (msg) {
                fetch('https://hud/sendChat', {
                    method: 'POST',
                    body: JSON.stringify({ message: msg })
                });
            }
            closeChatInput();
        } else if (e.key === 'Escape') {
            closeChatInput();
        }
    });
})();
