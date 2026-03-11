(() => {
    'use strict';

    // ========================
    // State
    // ========================
    let playerData = null;
    let isQueuing = false;

    const tierOrder = ['bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist', 'custom'];
    const tierLabels = {
        bronze: 'BRONZE', silver: 'SILVER', gold: 'GOLD',
        platinum: 'PLATINUM', diamond: 'DIAMOND', blacklist: 'BLACKLIST',
        custom: 'POLICE'
    };
    const tierLetters = {
        bronze: 'B', silver: 'S', gold: 'G',
        platinum: 'P', diamond: 'D', blacklist: 'X', custom: 'C'
    };
    const tierThresholds = {
        bronze: { min: 0, max: 500 },
        silver: { min: 501, max: 650 },
        gold: { min: 651, max: 800 },
        platinum: { min: 801, max: 950 },
        diamond: { min: 951, max: 1100 },
        blacklist: { min: 1101, max: 99999 }
    };

    // ========================
    // DOM refs
    // ========================
    const app = document.getElementById('app');
    const navButtons = document.querySelectorAll('.nav-btn');
    const pages = document.querySelectorAll('.page');

    // Sidebar
    const sidebarTierBadge = document.getElementById('sidebarTierBadge');
    const sidebarPlayerName = document.getElementById('sidebarPlayerName');
    const sidebarPlayerMMR = document.getElementById('sidebarPlayerMMR');

    // Play page
    const btnRanked = document.getElementById('btnRanked');
    const btnNormalChase = document.getElementById('btnNormalChase');
    const btnFreeRoam = document.getElementById('btnFreeRoam');
    const queueStatus = document.getElementById('queueStatus');
    const queueText = document.getElementById('queueText');
    const btnCancelQueue = document.getElementById('btnCancelQueue');

    // Sidebar action buttons
    const btnOpenMap = document.getElementById('btnOpenMap');
    const btnGTASettings = document.getElementById('btnGTASettings');
    const btnResumeFreeRoam = document.getElementById('btnResumeFreeRoam');
    let isInFreeRoam = false;

    // Profile
    const profileTierBadge = document.getElementById('profileTierBadge');
    const profileTierName = document.getElementById('profileTierName');
    const profilePlayerName = document.getElementById('profilePlayerName');
    const profileMMR = document.getElementById('profileMMR');

    // Chat
    const chatMessages = document.getElementById('chatMessages');
    const chatInput = document.getElementById('chatInput');
    const chatSend = document.getElementById('chatSend');

    // Garage
    const vehicleGrid = document.getElementById('vehicleGrid');
    const garageTierFilter = document.getElementById('garageTierFilter');
    const garageActionBar = document.getElementById('garageActionBar');
    const actionBarName = document.getElementById('actionBarName');
    const btnTune = document.getElementById('btnTune');
    let selectedGarageModel = null;

    // BlackList
    const blacklistRows = document.getElementById('blacklistRows');

    // ========================
    // Navigation
    // ========================
    navButtons.forEach(btn => {
        btn.addEventListener('click', () => {
            const page = btn.dataset.page;
            switchPage(page);

            if (page === 'blacklist') {
                fetch('https://menu/requestBlacklist', { method: 'POST', body: '{}' });
            } else if (page === 'garage') {
                fetch('https://menu/requestVehicles', { method: 'POST', body: '{}' });
            }
        });
    });

    function switchPage(pageName) {
        navButtons.forEach(b => b.classList.toggle('active', b.dataset.page === pageName));
        pages.forEach(p => p.classList.toggle('active', p.id === 'page-' + pageName));
    }

    // ========================
    // Mode buttons
    // ========================
    const crossTierToggle = document.getElementById('crossTierToggle');
    const testRankedToggle = document.getElementById('testRankedToggle');

    btnRanked.addEventListener('click', () => {
        if (isQueuing) return;
        const crossTier = crossTierToggle ? crossTierToggle.checked : false;
        const testMode = testRankedToggle ? testRankedToggle.checked : false;
        fetch('https://menu/joinRanked', {
            method: 'POST',
            body: JSON.stringify({ crossTier, testMode })
        });
        const msg = testMode ? 'Finding test ranked match...'
            : crossTier ? 'Finding cross-tier ranked match...'
            : 'Finding ranked match...';
        showQueue(msg);
    });

    btnNormalChase.addEventListener('click', () => {
        if (isQueuing) return;
        fetch('https://menu/joinNormalChase', { method: 'POST', body: '{}' });
        showQueue('Finding chase lobby...');
    });

    btnFreeRoam.addEventListener('click', () => {
        fetch('https://menu/joinFreeRoam', { method: 'POST', body: '{}' });
    });

    // Solo test
    const btnSoloTest = document.getElementById('btnSoloTest');
    const soloTestConfig = document.getElementById('soloTestConfig');
    const btnSoloStart = document.getElementById('btnSoloStart');
    let soloMode = 'ranked';
    let soloRole = 'runner';

    btnSoloTest.addEventListener('click', () => {
        soloTestConfig.classList.toggle('hidden');
    });

    soloTestConfig.querySelectorAll('[data-solo-mode]').forEach(btn => {
        btn.addEventListener('click', () => {
            soloTestConfig.querySelectorAll('[data-solo-mode]').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            soloMode = btn.dataset.soloMode;
        });
    });

    soloTestConfig.querySelectorAll('[data-solo-role]').forEach(btn => {
        btn.addEventListener('click', () => {
            soloTestConfig.querySelectorAll('[data-solo-role]').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            soloRole = btn.dataset.soloRole;
        });
    });

    btnSoloStart.addEventListener('click', () => {
        if (isQueuing) return;
        fetch('https://menu/joinSoloTest', {
            method: 'POST',
            body: JSON.stringify({ mode: soloMode, role: soloRole })
        });
        showQueue('Starting solo test...');
    });

    btnOpenMap.addEventListener('click', () => {
        fetch('https://menu/openMap', { method: 'POST', body: '{}' });
    });

    btnGTASettings.addEventListener('click', () => {
        fetch('https://menu/openGTASettings', { method: 'POST', body: '{}' });
    });

    btnResumeFreeRoam.addEventListener('click', () => {
        fetch('https://menu/resumeFreeRoam', { method: 'POST', body: '{}' });
    });

    btnCancelQueue.addEventListener('click', () => {
        fetch('https://menu/leaveQueue', { method: 'POST', body: '{}' });
        hideQueue();
    });

    document.getElementById('btnLeaveServer').addEventListener('click', () => {
        fetch('https://menu/leaveServer', { method: 'POST', body: '{}' });
    });

    function showQueue(text) {
        isQueuing = true;
        queueStatus.classList.remove('hidden');
        queueText.textContent = text;
    }

    function hideQueue() {
        isQueuing = false;
        queueStatus.classList.add('hidden');
    }

    // ========================
    // Chat
    // ========================
    function sendChat() {
        const msg = chatInput.value.trim();
        if (!msg) return;
        fetch('https://menu/sendChat', { method: 'POST', body: JSON.stringify({ message: msg }) });
        chatInput.value = '';
    }

    chatSend.addEventListener('click', sendChat);
    chatInput.addEventListener('keydown', e => {
        if (e.key === 'Enter') sendChat();
    });

    function addChatMessage(data) {
        const el = document.createElement('div');
        el.classList.add('chat-msg');

        const badge = document.createElement('span');
        badge.classList.add('chat-msg-badge', 'badge-' + (data.tier || 'bronze'));
        badge.textContent = tierLetters[data.tier || 'bronze'];

        const name = document.createElement('span');
        name.classList.add('chat-msg-name');
        name.textContent = data.name || 'Unknown';

        const text = document.createElement('span');
        text.classList.add('chat-msg-text');
        text.textContent = data.message || '';

        el.appendChild(badge);
        el.appendChild(name);
        el.appendChild(text);
        chatMessages.appendChild(el);
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    // ========================
    // Update player UI
    // ========================
    function updatePlayerUI(data) {
        if (!data) return;
        playerData = data;

        const tier = data.tier || 'bronze';
        const mmr = data.mmr || 500;
        const name = data.name || 'Player';

        // Sidebar
        sidebarTierBadge.textContent = tierLetters[tier];
        sidebarTierBadge.className = 'player-tier-badge badge-' + tier;
        sidebarPlayerName.textContent = name;
        sidebarPlayerMMR.textContent = mmr + ' MMR';

        // Profile page
        const tierIcon = profileTierBadge.querySelector('.tier-icon');
        tierIcon.textContent = tierLetters[tier];
        tierIcon.className = 'tier-icon badge-' + tier;
        profileTierName.textContent = tierLabels[tier];
        profilePlayerName.textContent = name;
        profileMMR.textContent = mmr;

        document.getElementById('statWins').textContent = data.wins || 0;
        document.getElementById('statLosses').textContent = data.losses || 0;
        document.getElementById('statChases').textContent = data.chases_played || 0;
        document.getElementById('statEscapes').textContent = data.escapes_played || 0;

        const total = (data.wins || 0) + (data.losses || 0);
        const winRate = total > 0 ? Math.round((data.wins / total) * 100) : 0;
        document.getElementById('statWinRate').textContent = winRate + '%';
        document.getElementById('statVehicle').textContent = data.selected_vehicle || '-';

        // Tier progress
        const th = tierThresholds[tier];
        const tierIdx = tierOrder.indexOf(tier);
        const nextTier = tierIdx < tierOrder.length - 1 ? tierOrder[tierIdx + 1] : tier;

        document.getElementById('currentTierLabel').textContent = tierLabels[tier];
        document.getElementById('nextTierLabel').textContent = tierLabels[nextTier];

        const range = th.max - th.min;
        const progress = range > 0 ? ((mmr - th.min) / range) * 100 : 100;
        document.getElementById('tierProgressFill').style.width = Math.min(progress, 100) + '%';
        document.getElementById('tierProgressMMR').textContent = mmr + ' / ' + (th.max + 1);
    }

    // ========================
    // Vehicles / Garage
    // ========================
    function renderVehicles(catalog, owned) {
        vehicleGrid.innerHTML = '';
        garageTierFilter.innerHTML = '';

        const ownedMap = {};
        (owned || []).forEach(v => { ownedMap[v.model] = v; });

        const presentTiers = new Set((catalog || []).map(c => c.tier));
        const activeTiers = tierOrder.filter(t => presentTiers.has(t));

        // Tier filter buttons (only tiers with cars)
        let firstTier = null;
        activeTiers.forEach((tier, idx) => {
            if (idx === 0) firstTier = tier;
            const btn = document.createElement('button');
            btn.classList.add('tier-filter-btn');
            if (idx === 0) btn.classList.add('active');
            btn.textContent = tierLabels[tier];
            btn.dataset.tier = tier;
            btn.addEventListener('click', () => {
                garageTierFilter.querySelectorAll('.tier-filter-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                filterVehicles(tier);
            });
            garageTierFilter.appendChild(btn);
        });

        (catalog || []).forEach(car => {
            const card = document.createElement('div');
            card.classList.add('vehicle-card');
            card.dataset.tier = car.tier;
            card.dataset.model = car.model;

            const isOwned = ownedMap[car.model];
            const isSelected = isOwned && isOwned.is_selected;
            if (isSelected) card.classList.add('selected');

            card.innerHTML = `
                <div class="vehicle-name">${car.label}</div>
                <div class="vehicle-tier tier-${car.tier}">${tierLabels[car.tier]}</div>
                ${isSelected ? '<div class="vehicle-selected-badge"></div>' : ''}
            `;

            card.addEventListener('click', () => {
                // Select this car
                fetch('https://menu/selectVehicle', {
                    method: 'POST',
                    body: JSON.stringify({ model: car.model })
                });
                vehicleGrid.querySelectorAll('.vehicle-card').forEach(c => {
                    c.classList.remove('selected');
                    const badge = c.querySelector('.vehicle-selected-badge');
                    if (badge) badge.remove();
                });
                card.classList.add('selected');
                const badgeEl = document.createElement('div');
                badgeEl.classList.add('vehicle-selected-badge');
                card.appendChild(badgeEl);

                // Show action bar with TUNE
                selectedGarageModel = car.model;
                actionBarName.textContent = car.label;
                garageActionBar.classList.remove('hidden');
            });

            vehicleGrid.appendChild(card);
        });

        if (firstTier) filterVehicles(firstTier);
    }

    function filterVehicles(tier) {
        vehicleGrid.querySelectorAll('.vehicle-card').forEach(card => {
            card.style.display = card.dataset.tier === tier ? '' : 'none';
        });
    }

    btnTune.addEventListener('click', () => {
        if (!selectedGarageModel) return;
        fetch('https://menu/enterGarage', {
            method: 'POST',
            body: JSON.stringify({ model: selectedGarageModel })
        });
    });

    // ========================
    // BlackList
    // ========================
    function renderBlacklist(data) {
        blacklistRows.innerHTML = '';
        (data || []).forEach((player, i) => {
            const row = document.createElement('div');
            row.classList.add('blacklist-row');
            if (i < 3) row.classList.add('top3');

            row.innerHTML = `
                <span class="bl-pos">${i + 1}</span>
                <span class="bl-name">${player.name}</span>
                <span class="bl-tier tier-${player.tier}">${tierLabels[player.tier] || player.tier.toUpperCase()}</span>
                <span class="bl-mmr">${player.mmr}</span>
                <span class="bl-record">${player.wins || 0} / ${player.losses || 0}</span>
            `;
            blacklistRows.appendChild(row);
        });
    }

    // ========================
    // NUI message handler
    // ========================
    window.addEventListener('message', (event) => {
        const data = event.data;

        switch (data.action) {
            case 'showMenu':
                if (data.show) {
                    app.classList.remove('hidden');
                    isInFreeRoam = !!data.fromFreeRoam;
                    btnOpenMap.classList.toggle('hidden', !isInFreeRoam);
                    btnGTASettings.classList.toggle('hidden', !isInFreeRoam);
                    btnResumeFreeRoam.classList.toggle('hidden', !isInFreeRoam);
                } else {
                    app.classList.add('hidden');
                }
                break;

            case 'playerData':
                updatePlayerUI(data.player);
                break;

            case 'chatMessage':
                addChatMessage(data.message);
                break;

            case 'blacklistData':
                renderBlacklist(data.blacklist);
                break;

            case 'vehicleData':
                renderVehicles(data.catalog, data.owned);
                break;

            case 'queueUpdate':
                if (data.queue) {
                    if (data.queue.status === 'matched') {
                        hideQueue();
                    } else if (data.queue.status === 'waiting') {
                        showQueue(data.queue.message || 'In queue...');
                    } else if (data.queue.status === 'cancelled') {
                        hideQueue();
                    }
                }
                break;
        }
    });

    // ESC key closes menu and resumes freeroam (NUI eats the keypress so Lua never sees it)
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && isInFreeRoam) {
            fetch('https://menu/resumeFreeRoam', { method: 'POST', body: '{}' });
        }
    });

    // Background slideshow
    const menuSlides = document.querySelectorAll('.menu-slide');
    let currentMenuSlide = 0;

    function cycleMenuSlides() {
        if (menuSlides.length <= 1) return;
        menuSlides[currentMenuSlide].classList.remove('active');
        currentMenuSlide = (currentMenuSlide + 1) % menuSlides.length;
        menuSlides[currentMenuSlide].classList.add('active');
    }

    setInterval(cycleMenuSlides, 7000);
})();
