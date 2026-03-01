(() => {
    'use strict';

    const hud = document.getElementById('hud');
    const speedValue = document.getElementById('speedValue');
    const gearValue = document.getElementById('gearValue');
    const rpmFill = document.getElementById('rpmFill');
    const tierLetter = document.getElementById('hudTierLetter');

    const tierLetters = {
        bronze: 'B', silver: 'S', gold: 'G',
        platinum: 'P', diamond: 'D', blacklist: 'X'
    };

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
        }
    });
})();
