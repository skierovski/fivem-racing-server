(() => {
    'use strict';

    // ========================
    // State
    // ========================
    let playerData = null;
    let isQueuing = false;
    let currentSubpageMode = null;

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

    const MODE_CONFIG = {
        ranked: {
            title: 'RANKED',
            subtitle: 'Competitive 1v1 Elo-rated matches',
            icon: '<svg viewBox="0 0 24 24" width="36" height="36"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>',
            queueText: 'Finding ranked match...',
            fetchEndpoint: 'joinRanked',
            infoTags: ['1v1', 'ELO RATED', 'SAME CAR'],
            infoText: 'Both players drive the same randomly assigned car from the matched tier. Winner gains MMR, loser loses MMR. Climb through Bronze, Silver, Gold, Platinum, Diamond and reach the Blacklist.',
            hasOptions: true,
            hasSolo: true,
        },
        normal: {
            title: 'CHASE',
            subtitle: 'Bank Heist Escape — 1 runner vs up to 4 chasers',
            icon: '<svg viewBox="0 0 24 24" width="36" height="36"><path fill="currentColor" d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/></svg>',
            queueText: 'Finding chase lobby...',
            fetchEndpoint: 'joinNormalChase',
            infoTags: ['1v4', 'PD vs RUNNER', 'PICK YOUR CAR'],
            infoText: 'One runner escapes in a car of their choice while up to 4 police chasers and a helicopter try to catch them. Runner picks any unlocked car, chasers get assigned PD vehicles. Code escalation from Green to Red.',
            hasOptions: true,
            hasSolo: true,
        },
    };

    // ========================
    // DOM refs
    // ========================
    const app = document.getElementById('app');
    const navButtons = document.querySelectorAll('.nav-btn[data-page]');
    const pages = document.querySelectorAll('.page');

    // Sidebar
    const sidebarTierBadge = document.getElementById('sidebarTierBadge');
    const sidebarPlayerName = document.getElementById('sidebarPlayerName');
    const sidebarPlayerMMR = document.getElementById('sidebarPlayerMMR');

    // Play page — overview
    const modeOverview = document.getElementById('modeOverview');
    const btnRanked = document.getElementById('btnRanked');
    const btnNormalChase = document.getElementById('btnNormalChase');
    const btnFreeRoam = document.getElementById('btnFreeRoam');

    // Play page — subpage
    const modeSubpage = document.getElementById('modeSubpage');
    const btnSubpageBack = document.getElementById('btnSubpageBack');
    const subpageModeIcon = document.getElementById('subpageModeIcon');
    const subpageTitle = document.getElementById('subpageTitle');
    const subpageSubtitle = document.getElementById('subpageSubtitle');
    const btnSubpageQueue = document.getElementById('btnSubpageQueue');
    const subpageQueueStatus = document.getElementById('subpageQueueStatus');
    const subpageQueueText = document.getElementById('subpageQueueText');
    const btnSubpageCancelQueue = document.getElementById('btnSubpageCancelQueue');
    const subpageOptions = document.getElementById('subpageOptions');
    const subpageSoloSection = document.getElementById('subpageSoloSection');
    const btnSoloToggle = document.getElementById('btnSoloToggle');
    const subpageSoloConfig = document.getElementById('subpageSoloConfig');
    const btnSubpageSoloStart = document.getElementById('btnSubpageSoloStart');
    const subpageInfo = document.getElementById('subpageInfo');
    const subpageMatches = document.getElementById('subpageMatches');
    const subpageLeaderboard = document.getElementById('subpageLeaderboard');

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

    // Solo test state
    let soloRole = 'runner';

    // Chase role preferences (at least 2 of 3 must be selected)
    let chaseRoles = { runner: true, chaser: true, heli: false };

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

            if (page === 'main') {
                closeSubpage();
            }
        });
    });

    function switchPage(pageName) {
        navButtons.forEach(b => b.classList.toggle('active', b.dataset.page === pageName));
        pages.forEach(p => p.classList.toggle('active', p.id === 'page-' + pageName));
    }

    // ========================
    // Mode card clicks → open sub-page
    // ========================
    btnRanked.addEventListener('click', () => openSubpage('ranked'));
    btnNormalChase.addEventListener('click', () => openSubpage('normal'));

    btnFreeRoam.addEventListener('click', () => {
        fetch('https://menu/joinFreeRoam', { method: 'POST', body: '{}' });
    });

    // ========================
    // Sub-page logic
    // ========================
    function updateChaseQueueBtn() {
        const count = Object.values(chaseRoles).filter(Boolean).length;
        if (btnSubpageQueue) {
            btnSubpageQueue.classList.toggle('disabled', count < 2);
        }
    }

    function openSubpage(mode) {
        const cfg = MODE_CONFIG[mode];
        if (!cfg) return;

        currentSubpageMode = mode;

        subpageModeIcon.innerHTML = cfg.icon;
        subpageTitle.textContent = cfg.title;
        subpageSubtitle.textContent = cfg.subtitle;

        // Queue state
        btnSubpageQueue.classList.toggle('hidden', isQueuing);
        subpageQueueStatus.classList.toggle('hidden', !isQueuing);

        // Options (ranked toggles or chase role selection)
        subpageOptions.innerHTML = '';
        if (cfg.hasOptions && mode === 'ranked') {
            subpageOptions.innerHTML = `
                <div class="cross-tier-option">
                    <label class="toggle-label">
                        <input type="checkbox" id="subCrossTierToggle" class="toggle-input">
                        <span class="toggle-switch"></span>
                        <span class="toggle-text">CROSS-TIER QUEUE</span>
                    </label>
                    <span class="cross-tier-desc">Match against players one tier above or below</span>
                </div>
                <div class="cross-tier-option">
                    <label class="toggle-label">
                        <input type="checkbox" id="subTestRankedToggle" class="toggle-input">
                        <span class="toggle-switch"></span>
                        <span class="toggle-text">TEST RANKED</span>
                    </label>
                    <span class="cross-tier-desc">No MMR matching, random car from any tier</span>
                </div>
            `;
        } else if (cfg.hasOptions && mode === 'normal') {
            subpageOptions.innerHTML = `
                <div class="role-select-section">
                    <div class="role-select-title">ROLE PREFERENCE <span class="role-select-hint">Pick at least 2</span></div>
                    <div class="role-select-grid">
                        <button class="role-select-btn ${chaseRoles.runner ? 'active' : ''}" data-role="runner">
                            <svg viewBox="0 0 24 24" width="28" height="28"><path fill="currentColor" d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/></svg>
                            <span>RUNNER</span>
                        </button>
                        <button class="role-select-btn ${chaseRoles.chaser ? 'active' : ''}" data-role="chaser">
                            <svg viewBox="0 0 24 24" width="28" height="28"><path fill="currentColor" d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 6c1.4 0 2.5 1.1 2.5 2.5S13.4 12 12 12s-2.5-1.1-2.5-2.5S10.6 7 12 7zm5 10H7v-1.25C7 13.92 9.67 13 12 13s5 .92 5 2.75V17z"/></svg>
                            <span>CHASER</span>
                        </button>
                        <button class="role-select-btn ${chaseRoles.heli ? 'active' : ''}" data-role="heli">
                            <svg viewBox="0 0 24 24" width="28" height="28"><path fill="currentColor" d="M21 16v-2l-8-5V3.5c0-.83-.67-1.5-1.5-1.5S10 2.67 10 3.5V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5l8 2.5z"/></svg>
                            <span>HELI PILOT</span>
                        </button>
                    </div>
                    <div class="role-select-warn hidden" id="roleSelectWarn">Select at least 2 roles to queue</div>
                </div>
            `;
            subpageOptions.querySelectorAll('.role-select-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    const role = btn.dataset.role;
                    const wouldDisable = chaseRoles[role];
                    const activeCount = Object.values(chaseRoles).filter(Boolean).length;
                    if (wouldDisable && activeCount <= 2) {
                        const warn = document.getElementById('roleSelectWarn');
                        if (warn) { warn.classList.remove('hidden'); setTimeout(() => warn.classList.add('hidden'), 2000); }
                        return;
                    }
                    chaseRoles[role] = !chaseRoles[role];
                    btn.classList.toggle('active', chaseRoles[role]);
                    updateChaseQueueBtn();
                });
            });
            updateChaseQueueBtn();
        }

        // Solo test section
        if (cfg.hasSolo) {
            subpageSoloSection.classList.remove('hidden');
            subpageSoloConfig.classList.add('hidden');
            btnSoloToggle.classList.remove('open');
            soloRole = 'runner';
            subpageSoloConfig.querySelectorAll('[data-sub-solo-role]').forEach(b => {
                b.classList.toggle('active', b.dataset.subSoloRole === 'runner');
            });
        } else {
            subpageSoloSection.classList.add('hidden');
        }

        // Info
        subpageInfo.innerHTML = '';
        const tagsHtml = cfg.infoTags.map(t => `<span class="subpage-info-tag">${t}</span>`).join('');
        subpageInfo.innerHTML = `<div>${tagsHtml}</div><p class="subpage-info-text">${cfg.infoText}</p>`;

        // Reset data sections
        subpageMatches.innerHTML = '<div class="subpage-empty">Loading...</div>';
        subpageLeaderboard.innerHTML = '<div class="subpage-empty">Loading...</div>';

        // Show subpage, hide overview
        modeOverview.classList.add('hidden');
        modeSubpage.classList.remove('hidden');

        // Fetch data
        fetch('https://menu/requestRecentMatches', {
            method: 'POST',
            body: JSON.stringify({ mode: mode })
        });
        fetch('https://menu/requestModeLeaderboard', {
            method: 'POST',
            body: JSON.stringify({ mode: mode })
        });
    }

    function closeSubpage() {
        currentSubpageMode = null;
        modeSubpage.classList.add('hidden');
        modeOverview.classList.remove('hidden');
    }

    btnSubpageBack.addEventListener('click', closeSubpage);

    // ========================
    // Queue (inside sub-page)
    // ========================
    btnSubpageQueue.addEventListener('click', () => {
        if (isQueuing || !currentSubpageMode) return;
        const mode = currentSubpageMode;
        const cfg = MODE_CONFIG[mode];

        if (mode === 'ranked') {
            const crossTier = document.getElementById('subCrossTierToggle');
            const testMode = document.getElementById('subTestRankedToggle');
            fetch('https://menu/joinRanked', {
                method: 'POST',
                body: JSON.stringify({
                    crossTier: crossTier ? crossTier.checked : false,
                    testMode: testMode ? testMode.checked : false,
                })
            });
            const msg = (testMode && testMode.checked) ? 'Finding test ranked match...'
                : (crossTier && crossTier.checked) ? 'Finding cross-tier ranked match...'
                : 'Finding ranked match...';
            showSubpageQueue(msg);
        } else if (mode === 'normal') {
            const activeCount = Object.values(chaseRoles).filter(Boolean).length;
            if (activeCount < 2) return;
            fetch('https://menu/joinNormalChase', {
                method: 'POST',
                body: JSON.stringify({ roles: chaseRoles }),
            });
            showSubpageQueue(cfg.queueText);
        }
    });

    btnSubpageCancelQueue.addEventListener('click', () => {
        fetch('https://menu/leaveQueue', { method: 'POST', body: '{}' });
        hideSubpageQueue();
    });

    function showSubpageQueue(text) {
        isQueuing = true;
        btnSubpageQueue.classList.add('hidden');
        subpageQueueStatus.classList.remove('hidden');
        subpageQueueText.textContent = text;
    }

    function hideSubpageQueue() {
        isQueuing = false;
        btnSubpageQueue.classList.remove('hidden');
        subpageQueueStatus.classList.add('hidden');
    }

    // ========================
    // Solo test (inside sub-page)
    // ========================
    btnSoloToggle.addEventListener('click', () => {
        const isOpen = !subpageSoloConfig.classList.contains('hidden');
        subpageSoloConfig.classList.toggle('hidden', isOpen);
        btnSoloToggle.classList.toggle('open', !isOpen);
    });

    subpageSoloConfig.querySelectorAll('[data-sub-solo-role]').forEach(btn => {
        btn.addEventListener('click', () => {
            subpageSoloConfig.querySelectorAll('[data-sub-solo-role]').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            soloRole = btn.dataset.subSoloRole;
        });
    });

    btnSubpageSoloStart.addEventListener('click', () => {
        if (isQueuing || !currentSubpageMode) return;
        const soloMode = currentSubpageMode === 'normal' ? 'normal' : 'ranked';
        fetch('https://menu/joinSoloTest', {
            method: 'POST',
            body: JSON.stringify({ mode: soloMode, role: soloRole })
        });
        showSubpageQueue('Starting solo test...');
    });

    // ========================
    // Sidebar actions
    // ========================
    btnOpenMap.addEventListener('click', () => {
        fetch('https://menu/openMap', { method: 'POST', body: '{}' });
    });

    btnGTASettings.addEventListener('click', () => {
        fetch('https://menu/openGTASettings', { method: 'POST', body: '{}' });
    });

    btnResumeFreeRoam.addEventListener('click', () => {
        fetch('https://menu/resumeFreeRoam', { method: 'POST', body: '{}' });
    });

    document.getElementById('btnLeaveServer').addEventListener('click', () => {
        fetch('https://menu/leaveServer', { method: 'POST', body: '{}' });
    });

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

        sidebarTierBadge.textContent = tierLetters[tier];
        sidebarTierBadge.className = 'player-tier-badge badge-' + tier;
        sidebarPlayerName.textContent = name;
        sidebarPlayerMMR.textContent = mmr + ' MMR';

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
                fetch('https://menu/selectVehicle', {
                    method: 'POST',
                    body: JSON.stringify({ model: car.model })
                });
                vehicleGrid.querySelectorAll('.vehicle-card').forEach(c => {
                    c.classList.remove('selected');
                    const b = c.querySelector('.vehicle-selected-badge');
                    if (b) b.remove();
                });
                card.classList.add('selected');
                const badgeEl = document.createElement('div');
                badgeEl.classList.add('vehicle-selected-badge');
                card.appendChild(badgeEl);

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
    // Recent matches renderer
    // ========================
    function renderRecentMatches(matches) {
        subpageMatches.innerHTML = '';
        if (!matches || matches.length === 0) {
            subpageMatches.innerHTML = '<div class="subpage-empty">No recent matches</div>';
            return;
        }

        matches.forEach(m => {
            const row = document.createElement('div');
            row.classList.add('match-row');

            const isWin = m.result === 'win';
            const mmrSign = m.mmrChange >= 0 ? '+' : '';

            row.innerHTML = `
                <span class="match-opponent">${m.opponent || 'Unknown'}</span>
                <span class="match-result ${isWin ? 'win' : 'loss'}">${isWin ? 'WIN' : 'LOSS'}</span>
                <span class="match-mmr ${m.mmrChange >= 0 ? 'positive' : 'negative'}">${mmrSign}${m.mmrChange || 0}</span>
                <span class="match-duration">${formatDuration(m.duration || 0)}</span>
            `;
            subpageMatches.appendChild(row);
        });
    }

    function formatDuration(seconds) {
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ':' + (s < 10 ? '0' : '') + s;
    }

    // ========================
    // Mode leaderboard renderer
    // ========================
    function renderModeLeaderboard(players) {
        subpageLeaderboard.innerHTML = '';
        if (!players || players.length === 0) {
            subpageLeaderboard.innerHTML = '<div class="subpage-empty">No data</div>';
            return;
        }

        players.forEach((p, i) => {
            const row = document.createElement('div');
            row.classList.add('lb-row');

            row.innerHTML = `
                <span class="lb-pos">${i + 1}</span>
                <span class="lb-name">${p.name}</span>
                <span class="lb-tier tier-${p.tier}">${tierLabels[p.tier] || p.tier.toUpperCase()}</span>
                <span class="lb-mmr">${p.mmr}</span>
            `;
            subpageLeaderboard.appendChild(row);
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
                    if (data.queue.status === 'matched' || data.queue.status === 'cancelled') {
                        hideSubpageQueue();
                    } else if (data.queue.status === 'waiting') {
                        showSubpageQueue(data.queue.message || 'In queue...');
                    }
                }
                break;

            case 'recentMatchesData':
                renderRecentMatches(data.matches);
                break;

            case 'modeLeaderboardData':
                renderModeLeaderboard(data.players);
                break;
        }
    });

    // ESC key: in freeroam resume, in subpage go back to overview
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (isInFreeRoam) {
                fetch('https://menu/resumeFreeRoam', { method: 'POST', body: '{}' });
            } else if (currentSubpageMode && !isQueuing) {
                closeSubpage();
            }
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
