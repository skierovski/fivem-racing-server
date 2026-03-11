(() => {
    'use strict';

    const hint = document.getElementById('hint');
    const freeroamMenu = document.getElementById('freeroamMenu');
    const carList = document.getElementById('carList');
    const carSearch = document.getElementById('carSearch');
    const btnClose = document.getElementById('btnClose');
    const btnTeleport = document.getElementById('btnTeleport');
    const btnBack = document.getElementById('btnBack');

    let allVehicles = [];

    const tierLabels = {
        bronze: 'BRONZE', silver: 'SILVER', gold: 'GOLD',
        platinum: 'PLATINUM', diamond: 'DIAMOND', blacklist: 'BLACKLIST',
        custom: 'POLICE'
    };

    // ========================
    // Vehicle list rendering
    // ========================

    function renderVehicles(vehicles) {
        carList.innerHTML = '';
        vehicles.forEach(car => {
            const item = document.createElement('div');
            item.classList.add('fm-car-item');
            item.innerHTML = `
                <span class="fm-car-name">${car.label}</span>
                <span class="fm-car-tier tier-${car.tier}">${tierLabels[car.tier] || car.tier}</span>
            `;
            item.addEventListener('click', () => {
                fetch('https://freeroam/selectFreeroamCar', {
                    method: 'POST',
                    body: JSON.stringify({ model: car.model })
                });
            });
            carList.appendChild(item);
        });
    }

    function filterVehicles(query) {
        const q = query.toLowerCase();
        const filtered = allVehicles.filter(v =>
            v.label.toLowerCase().includes(q) || v.model.toLowerCase().includes(q)
        );
        renderVehicles(filtered);
    }

    carSearch.addEventListener('input', () => {
        filterVehicles(carSearch.value);
    });

    // ========================
    // Buttons
    // ========================

    btnClose.addEventListener('click', () => {
        fetch('https://freeroam/closeFreeroamMenu', { method: 'POST', body: '{}' });
    });

    btnTeleport.addEventListener('click', () => {
        fetch('https://freeroam/teleportToWaypoint', { method: 'POST', body: '{}' });
    });

    btnBack.addEventListener('click', () => {
        fetch('https://freeroam/backToMainMenu', { method: 'POST', body: '{}' });
    });

    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') {
            fetch('https://freeroam/closeFreeroamMenu', { method: 'POST', body: '{}' });
        }
    });

    // ========================
    // NUI message handler
    // ========================

    window.addEventListener('message', (event) => {
        const data = event.data;

        switch (data.action) {
            case 'showHint':
                hint.classList.toggle('hidden', !data.show);
                break;

            case 'openFreeroamMenu':
                freeroamMenu.classList.remove('hidden');
                carSearch.value = '';
                break;

            case 'closeFreeroamMenu':
                freeroamMenu.classList.add('hidden');
                break;

            case 'vehicleList':
                allVehicles = data.vehicles || [];
                renderVehicles(allVehicles);
                break;
        }
    });
})();
