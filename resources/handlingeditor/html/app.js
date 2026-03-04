const editor = document.getElementById('editor');
const fieldsContainer = document.getElementById('fieldsContainer');
const vehicleName = document.getElementById('vehicleName');
const searchInput = document.getElementById('searchInput');
const exportPanel = document.getElementById('exportPanel');
const exportText = document.getElementById('exportText');

let currentFields = [];

window.addEventListener('message', (event) => {
    const { action } = event.data;

    if (action === 'open') {
        currentFields = event.data.fields || [];
        vehicleName.textContent = event.data.vehicle || '';
        renderFields(currentFields);
        editor.classList.remove('hidden');
        searchInput.value = '';
        searchInput.focus();
    }

    if (action === 'close') {
        editor.classList.add('hidden');
        exportPanel.classList.add('hidden');
    }
});

function renderFields(fields) {
    const filter = searchInput.value.toLowerCase();
    fieldsContainer.innerHTML = '';

    fields.forEach(field => {
        if (filter && !field.name.toLowerCase().includes(filter) && !field.desc.toLowerCase().includes(filter)) {
            return;
        }

        const row = document.createElement('div');
        row.className = 'field-row';

        const info = document.createElement('div');
        info.className = 'field-info';

        const name = document.createElement('div');
        name.className = 'field-name';
        name.textContent = field.name;

        const desc = document.createElement('div');
        desc.className = 'field-desc';
        desc.textContent = field.desc;

        info.appendChild(name);
        info.appendChild(desc);

        const val = document.createElement('div');
        val.className = 'field-value';
        val.textContent = formatValue(field.value, field.type);

        row.appendChild(info);
        row.appendChild(val);
        fieldsContainer.appendChild(row);
    });
}

function formatValue(value, type) {
    if (type === 'int') return Math.floor(value).toString();
    if (typeof value === 'number') return value.toFixed(4);
    return value;
}

searchInput.addEventListener('input', () => renderFields(currentFields));

searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        e.preventDefault();
        fetch('https://handlingeditor/close', { method: 'POST', body: JSON.stringify({}) });
    }
    e.stopPropagation();
});

document.getElementById('btnClose').addEventListener('click', () => {
    fetch('https://handlingeditor/close', { method: 'POST', body: JSON.stringify({}) });
});

document.getElementById('btnRefresh').addEventListener('click', () => {
    fetch('https://handlingeditor/getValues', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(r => r.json()).then(res => {
        currentFields = res.fields || [];
        renderFields(currentFields);
    });
});

document.getElementById('btnExport').addEventListener('click', () => {
    fetch('https://handlingeditor/exportMeta', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(r => r.json()).then(res => {
        exportText.value = res.xml || '';
        exportPanel.classList.remove('hidden');
    });
});

document.getElementById('btnCloseExport').addEventListener('click', () => {
    exportPanel.classList.add('hidden');
});

document.getElementById('btnCopyExport').addEventListener('click', () => {
    exportText.select();
    document.execCommand('copy');
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !editor.classList.contains('hidden')) {
        fetch('https://handlingeditor/close', { method: 'POST', body: JSON.stringify({}) });
    }
});
