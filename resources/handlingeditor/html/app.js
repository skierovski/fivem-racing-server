const editor = document.getElementById('editor');
const fieldsContainer = document.getElementById('fieldsContainer');
const vehicleName = document.getElementById('vehicleName');
const searchInput = document.getElementById('searchInput');
const exportPanel = document.getElementById('exportPanel');
const exportText = document.getElementById('exportText');

let originalValues = {};
let currentFields = [];

window.addEventListener('message', (event) => {
    const { action } = event.data;

    if (action === 'open') {
        currentFields = event.data.fields || [];
        vehicleName.textContent = event.data.vehicle || '';
        originalValues = {};
        currentFields.forEach(f => { originalValues[f.name] = f.value; });
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
        const isModified = originalValues[field.name] !== undefined && 
            Math.abs(field.value - originalValues[field.name]) > 0.0001;
        if (isModified) row.classList.add('modified');

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

        const input = document.createElement('input');
        input.className = 'field-value';
        if (isModified) input.classList.add('changed');
        input.type = 'text';
        input.value = formatValue(field.value, field.type);
        input.dataset.fieldName = field.name;
        input.dataset.fieldType = field.type;

        if (field.readonly) {
            input.classList.add('readonly');
            input.readOnly = true;
            input.title = 'Read-only — edit handling.meta + restart server';
            desc.textContent = field.desc + ' (restart only)';
        }

        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                if (!field.readonly) applyValue(field.name, input.value);
                input.blur();
            }
            if (e.key === 'Escape') {
                e.preventDefault();
                input.blur();
            }
            e.stopPropagation();
        });

        input.addEventListener('focus', () => { if (!field.readonly) input.select(); });

        row.appendChild(info);
        row.appendChild(input);
        fieldsContainer.appendChild(row);
    });
}

function formatValue(value, type) {
    if (type === 'int') return Math.floor(value).toString();
    if (typeof value === 'number') return value.toFixed(4);
    return value;
}

function applyValue(name, rawValue) {
    const value = parseFloat(rawValue);
    if (isNaN(value)) return;

    fetch('https://handlingeditor/setValue', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, value })
    }).then(r => r.json()).then(res => {
        if (res.ok) {
            const field = currentFields.find(f => f.name === name);
            if (field) field.value = res.value;
            renderFields(currentFields);
        }
    });
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
