(() => {
    'use strict';

    const countdownOverlay = document.getElementById('countdownOverlay');
    const countdownNumber = document.getElementById('countdownNumber');
    const roleAnnounce = document.getElementById('roleAnnounce');
    const roleText = document.getElementById('roleText');
    const roleSub = document.getElementById('roleSub');
    const headstartBanner = document.getElementById('headstartBanner');
    const headstartText = document.getElementById('headstartText');
    const chaseHud = document.getElementById('chaseHud');
    const hudTimer = document.getElementById('hudTimer');
    const hudRole = document.getElementById('hudRole');
    const distanceValue = document.getElementById('distanceValue');
    const warningPopup = document.getElementById('warningPopup');
    const warningText = document.getElementById('warningText');
    const matchEnd = document.getElementById('matchEnd');
    const endResult = document.getElementById('endResult');
    const endDetails = document.getElementById('endDetails');

    let warningTimeout = null;

    function formatTime(seconds) {
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        return m + ':' + (s < 10 ? '0' : '') + s;
    }

    function hideAll() {
        countdownOverlay.classList.add('hidden');
        roleAnnounce.classList.add('hidden');
        headstartBanner.classList.add('hidden');
        chaseHud.classList.add('hidden');
        warningPopup.classList.add('hidden');
        matchEnd.classList.add('hidden');
    }

    window.addEventListener('message', (event) => {
        const data = event.data;

        switch (data.action) {
            case 'countdown': {
                hideAll();
                countdownOverlay.classList.remove('hidden');
                let count = data.seconds;
                countdownNumber.textContent = count;

                const interval = setInterval(() => {
                    count--;
                    if (count <= 0) {
                        clearInterval(interval);
                        countdownOverlay.classList.add('hidden');
                        countdownNumber.textContent = 'GO!';
                        setTimeout(() => countdownOverlay.classList.add('hidden'), 500);
                    } else {
                        countdownNumber.textContent = count;
                    }
                }, 1000);
                break;
            }

            case 'headstart': {
                countdownOverlay.classList.add('hidden');

                roleAnnounce.classList.remove('hidden');
                roleText.textContent = data.role === 'runner' ? 'RUNNER' : 'CHASER';
                roleText.className = 'role-text ' + data.role;
                roleSub.textContent = data.role === 'runner' ? 'Escape the chasers!' : 'Catch the runner!';

                if (data.role === 'chaser') {
                    headstartBanner.classList.remove('hidden');
                    let hs = data.duration;
                    headstartText.textContent = 'Runner head start: ' + hs + 's';
                    const hsInterval = setInterval(() => {
                        hs--;
                        if (hs <= 0) {
                            clearInterval(hsInterval);
                            headstartBanner.classList.add('hidden');
                        } else {
                            headstartText.textContent = 'Runner head start: ' + hs + 's';
                        }
                    }, 1000);
                }

                setTimeout(() => roleAnnounce.classList.add('hidden'), 3000);
                break;
            }

            case 'start': {
                roleAnnounce.classList.add('hidden');
                headstartBanner.classList.add('hidden');
                chaseHud.classList.remove('hidden');

                hudRole.textContent = data.role === 'runner' ? 'RUNNER' : 'CHASER';
                hudRole.className = 'hud-role ' + data.role;
                hudTimer.textContent = formatTime(data.duration);
                distanceValue.textContent = '---';
                break;
            }

            case 'timer': {
                hudTimer.textContent = formatTime(data.remaining);
                hudTimer.classList.toggle('danger', data.remaining <= 30);
                break;
            }

            case 'distance': {
                distanceValue.textContent = data.distance;
                break;
            }

            case 'warning': {
                warningPopup.classList.remove('hidden');
                warningText.textContent = data.message;
                if (warningTimeout) clearTimeout(warningTimeout);
                warningTimeout = setTimeout(() => {
                    warningPopup.classList.add('hidden');
                }, 4000);
                break;
            }

            case 'matchEnd': {
                hideAll();
                matchEnd.classList.remove('hidden');

                endResult.textContent = data.won ? 'VICTORY!' : 'DEFEAT';
                endResult.className = 'end-result ' + (data.won ? 'win' : 'loss');

                let detail = '';
                switch (data.reason) {
                    case 'time_expired':
                        detail = 'Runner escaped! Time ran out.';
                        break;
                    case 'caught':
                        detail = 'Runner was caught!';
                        break;
                    case 'runner_disqualified':
                        detail = 'Runner was disqualified.';
                        break;
                    case 'chaser_disqualified':
                        detail = 'Chaser was disqualified.';
                        break;
                    case 'runner_disconnected':
                        detail = 'Runner disconnected.';
                        break;
                    case 'all_chasers_disconnected':
                        detail = 'All chasers disconnected.';
                        break;
                    default:
                        detail = 'Match ended.';
                }
                detail += ' Duration: ' + formatTime(data.duration || 0);
                endDetails.textContent = detail;
                break;
            }
        }
    });
})();
