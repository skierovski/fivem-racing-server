(() => {
    'use strict';

    const speedo = document.getElementById('speedo');
    const speedNum = document.getElementById('speedNum');
    const speedUnit = document.getElementById('speedUnit');
    const gearVal = document.getElementById('gearVal');
    const rpmBar = document.getElementById('rpmBar');
    const healthBar = document.getElementById('healthBar');

    // Arc math: circumference = 2 * PI * 88 ≈ 553
    // We use 300 degrees of the circle (5/6), dasharray = 553 * (300/360) ≈ 461
    // But the SVG has stroke-dasharray: 396 and offset 96 for the background,
    // meaning visible arc = 396 - 96 = 300 units.
    const ARC_TOTAL = 396;
    const ARC_HIDDEN = 96;
    const ARC_VISIBLE = ARC_TOTAL - ARC_HIDDEN;

    function setRPM(rpm) {
        const clamped = Math.max(0, Math.min(1, rpm));
        const offset = ARC_TOTAL - (clamped * ARC_VISIBLE);
        rpmBar.style.strokeDashoffset = offset;

        if (clamped > 0.85) {
            speedo.classList.add('redline');
        } else {
            speedo.classList.remove('redline');
        }
    }

    function setGear(gear) {
        if (gear === 0) {
            gearVal.textContent = 'R';
        } else {
            gearVal.textContent = gear;
        }
    }

    function setHealth(pct) {
        healthBar.style.width = pct + '%';
    }

    window.addEventListener('message', (event) => {
        const d = event.data;

        switch (d.action) {
            case 'show':
                speedo.classList.toggle('hidden', !d.visible);
                break;

            case 'update':
                speedNum.textContent = d.speedMph;
                setRPM(d.rpm);
                setGear(d.gear);
                setHealth(d.health);
                break;
        }
    });
})();
