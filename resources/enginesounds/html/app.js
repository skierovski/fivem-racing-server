let sounds = [];
let filtered = [];
let selectedIdx = 0;
let appliedSound = null;

const panel = document.getElementById('panel');
const list = document.getElementById('list');
const search = document.getElementById('search');

function render() {
    list.innerHTML = '';

    const restoreEl = document.createElement('div');
    restoreEl.className = 'sound-item restore' + (selectedIdx === 0 ? ' selected' : '') + (appliedSound === '' ? ' applied' : '');
    restoreEl.textContent = 'Restore Default';
    restoreEl.addEventListener('click', () => applySound(''));
    list.appendChild(restoreEl);

    filtered.forEach((name, i) => {
        const idx = i + 1;
        const el = document.createElement('div');
        el.className = 'sound-item' + (idx === selectedIdx ? ' selected' : '') + (name === appliedSound ? ' applied' : '');
        el.textContent = name;
        el.addEventListener('click', () => applySound(name));
        list.appendChild(el);
    });

    const sel = list.querySelector('.selected');
    if (sel) sel.scrollIntoView({ block: 'nearest' });
}

function filter() {
    const q = search.value.toLowerCase().trim();
    filtered = q ? sounds.filter(s => s.toLowerCase().includes(q)) : [...sounds];
    selectedIdx = 0;
    render();
}

function applySound(name) {
    appliedSound = name;
    fetch('https://enginesounds/applySound', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sound: name })
    });
    render();
}

function closePanel() {
    panel.classList.add('hidden');
    search.value = '';
    fetch('https://enginesounds/close', { method: 'POST', body: '{}' });
}

window.addEventListener('message', (e) => {
    if (e.data.action === 'open') {
        sounds = e.data.sounds || [];
        filtered = [...sounds];
        selectedIdx = 0;
        appliedSound = null;
        panel.classList.remove('hidden');
        search.value = '';
        render();
        search.focus();
    }
});

document.addEventListener('keydown', (e) => {
    if (panel.classList.contains('hidden')) return;

    const total = filtered.length + 1;

    if (e.key === 'Escape') {
        e.preventDefault();
        closePanel();
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectedIdx = (selectedIdx + 1) % total;
        render();
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectedIdx = (selectedIdx - 1 + total) % total;
        render();
    } else if (e.key === 'Enter') {
        e.preventDefault();
        if (selectedIdx === 0) {
            applySound('');
        } else {
            applySound(filtered[selectedIdx - 1]);
        }
    }
});

search.addEventListener('input', filter);
