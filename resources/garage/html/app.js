(() => {
    'use strict';

    const app = document.getElementById('garageApp');
    const categoryList = document.getElementById('categoryList');
    const optionsPanel = document.getElementById('optionsPanel');
    const optionsHeader = document.getElementById('optionsHeader');
    const optionsList = document.getElementById('optionsList');
    const btnSave = document.getElementById('btnSave');
    const btnCancel = document.getElementById('btnCancel');

    let tuningData = null;
    let activeCategory = null;

    let COLOR_PRESETS = [];
    let WHEEL_COLORS = [];

    // Load color data from JSON
    fetch('../data/colors.json').then(r => r.json()).then(data => {
        COLOR_PRESETS = data.colorPresets || [];
        WHEEL_COLORS = data.wheelColors || [];
    }).catch(() => {});

    const CATEGORY_ICONS = {
        color1: '\u{1F3A8}', color2: '\u{1F3A8}',
        spoiler: '\u{1F3CE}', frontBumper: '\u{1F698}', rearBumper: '\u{1F698}',
        sideSkirts: '\u{1F3CE}', hood: '\u{1F3CE}',
        wheels: '\u{2699}', wheelColor: '\u{1F3A8}',
        livery: '\u{1F3AD}', windowTint: '\u{1F576}',
        neon: '\u{1F4A1}', turbo: '\u{26A1}', extras: '\u{1F6E0}',
        engine: '\u{1F527}', brakes: '\u{1F6D1}', transmission: '\u{2699}', suspension: '\u{1F4CF}',
    };

    let doorStates = { 0: false, 1: false, 2: false, 3: false, 4: false, 5: false };

    // WHEEL_COLORS is loaded from data/colors.json above

    // ========================
    // Message handler
    // ========================

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (data.action === 'openTuning') {
            tuningData = data;
            activeCategory = null;
            doorStates = { 0: false, 1: false, 2: false, 3: false, 4: false, 5: false };
            buildCategories();
            buildDoorToolbar();
            app.classList.remove('hidden');
            optionsPanel.classList.add('hidden');
        } else if (data.action === 'closeTuning') {
            app.classList.add('hidden');
            removeDoorToolbar();
            tuningData = null;
        }
    });

    // ========================
    // Build category sidebar
    // ========================

    function buildCategories() {
        categoryList.innerHTML = '';

        addSectionHeader('VISUAL');
        addCategory('color1', 'Primary Color', CATEGORY_ICONS.color1);
        addCategory('color2', 'Secondary Color', CATEGORY_ICONS.color2);
        addCategory('wheels', 'Wheels', CATEGORY_ICONS.wheels);
        addCategory('wheelColor', 'Rim Color', CATEGORY_ICONS.wheelColor);

        const visualMods = (tuningData.mods || []).filter(m =>
            ['spoiler', 'frontBumper', 'rearBumper', 'sideSkirts', 'hood'].includes(m.id)
        );
        visualMods.forEach(mod => {
            if (mod.count > 0) {
                addCategory(mod.id, mod.label, CATEGORY_ICONS[mod.id] || '\u{1F527}');
            }
        });

        if (tuningData.liveryCount > 0) {
            addCategory('livery', 'Livery', CATEGORY_ICONS.livery);
        }
        addCategory('windowTint', 'Window Tint', CATEGORY_ICONS.windowTint);
        addCategory('neon', 'Neon Underglow', CATEGORY_ICONS.neon);

        if ((tuningData.extras || []).length > 0) {
            addCategory('extras', 'Extras', CATEGORY_ICONS.extras);
        }
        addSectionHeader('PERFORMANCE');
        const perfMods = (tuningData.mods || []).filter(m =>
            ['engine', 'brakes', 'transmission', 'suspension'].includes(m.id)
        );
        perfMods.forEach(mod => {
            if (mod.count > 0) {
                addCategory(mod.id, mod.label, CATEGORY_ICONS[mod.id] || '\u{1F527}');
            }
        });
        addCategory('turbo', 'Turbo', CATEGORY_ICONS.turbo);
    }

    function addSectionHeader(label) {
        const div = document.createElement('div');
        div.className = 'cat-section';
        div.textContent = label;
        categoryList.appendChild(div);
    }

    function addCategory(id, label, icon) {
        const div = document.createElement('div');
        div.className = 'cat-item';
        div.dataset.cat = id;
        div.innerHTML = `<span class="cat-icon">${icon}</span><span>${label}</span>`;
        div.addEventListener('click', () => selectCategory(id, label));
        categoryList.appendChild(div);
    }

    function selectCategory(id, label) {
        activeCategory = id;
        categoryList.querySelectorAll('.cat-item').forEach(el => {
            el.classList.toggle('active', el.dataset.cat === id);
        });
        optionsPanel.classList.remove('hidden');
        optionsHeader.textContent = label.toUpperCase();
        renderOptions(id);
    }

    // ========================
    // Render options for a category
    // ========================

    function renderOptions(catId) {
        optionsList.innerHTML = '';

        if (catId === 'color1' || catId === 'color2') {
            renderColorPicker(catId);
        } else if (catId === 'wheelColor') {
            renderWheelColor();
        } else if (catId === 'wheels') {
            renderWheels();
        } else if (catId === 'windowTint') {
            renderWindowTint();
        } else if (catId === 'livery') {
            renderLivery();
        } else if (catId === 'neon') {
            renderNeon();
        } else if (catId === 'turbo') {
            renderTurbo();
        } else if (catId === 'extras') {
            renderExtras();
        } else {
            renderModSlot(catId);
        }
    }

    // ========================
    // Mod slot options (spoiler, bumpers, hood, engine, brakes, etc.)
    // ========================

    function renderModSlot(catId) {
        optionsList.innerHTML = '';
        const mod = (tuningData.mods || []).find(m => m.id === catId);
        if (!mod) return;

        const currentVal = mod.current;

        // Stock option
        addModOption('Stock', -1, currentVal === -1, mod.slot);

        for (let i = 0; i < mod.count; i++) {
            const isPerfSlot = [11, 12, 13, 15].includes(mod.slot);
            const label = isPerfSlot ? `Level ${i + 1}` : `Option ${i + 1}`;
            addModOption(label, i, currentVal === i, mod.slot);
        }
    }

    function addModOption(label, value, isActive, slot) {
        const div = document.createElement('div');
        div.className = 'opt-item' + (isActive ? ' active' : '');
        div.innerHTML = `<span>${label}</span>${isActive ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
        div.addEventListener('click', () => {
            fetch('https://garage/applyMod', {
                method: 'POST',
                body: JSON.stringify({ slot, value })
            });
            // Update local state
            const mod = (tuningData.mods || []).find(m => m.slot === slot);
            if (mod) mod.current = value;
            renderModSlot(activeCategory);
        });
        optionsList.appendChild(div);
    }

    // ========================
    // Color picker
    // ========================

    const PAINT_TYPES = [
        { id: 0, label: 'Normal' },
        { id: 1, label: 'Metallic' },
        { id: 3, label: 'Matte' },
        { id: 4, label: 'Metal' },
        { id: 5, label: 'Chrome' },
    ];

    function renderColorPicker(target) {
        optionsList.innerHTML = '';
        const area = document.createElement('div');
        area.className = 'color-picker-area';

        const key = target === 'color1' ? 'primary' : 'secondary';
        const cur = tuningData.currentColors[key] || { r: 0, g: 0, b: 0 };
        const ptKey = target === 'color1' ? 'paintType1' : 'paintType2';
        const activePT = tuningData[ptKey] || 0;

        const ptRow = document.createElement('div');
        ptRow.className = 'paint-type-selector';
        PAINT_TYPES.forEach(pt => {
            const btn = document.createElement('button');
            btn.className = 'paint-type-btn' + (pt.id === activePT ? ' active' : '');
            btn.textContent = pt.label;
            btn.addEventListener('click', () => {
                tuningData[ptKey] = pt.id;
                const nuiTarget = target === 'color1' ? 'primary' : 'secondary';
                fetch('https://garage/applyPaintType', {
                    method: 'POST',
                    body: JSON.stringify({ target: nuiTarget, paintType: pt.id })
                });
                renderColorPicker(target);
            });
            ptRow.appendChild(btn);
        });
        area.appendChild(ptRow);

        buildHSVPicker(area, cur, (r, g, b) => {
            cur.r = r; cur.g = g; cur.b = b;
            applyColor(target, r, g, b);
        });

        optionsList.appendChild(area);
    }

    function applyColor(target, r, g, b) {
        const nuiTarget = target === 'color1' ? 'primary' : 'secondary';
        fetch('https://garage/applyColor', {
            method: 'POST',
            body: JSON.stringify({ target: nuiTarget, r, g, b })
        });
    }

    // ========================
    // Wheels
    // ========================

    function renderWheels() {
        optionsList.innerHTML = '';
        const subHeader1 = document.createElement('div');
        subHeader1.className = 'options-sub-header';
        subHeader1.textContent = 'WHEEL TYPE';
        optionsList.appendChild(subHeader1);

        const curType = tuningData.currentWheelType || 0;
        const curIdx = tuningData.currentWheelIndex || -1;

        (tuningData.wheels || []).forEach(wt => {
            const isActive = wt.typeIndex === curType;
            const div = document.createElement('div');
            div.className = 'opt-item' + (isActive ? ' active' : '');
            div.innerHTML = `<span>${wt.label}</span>${isActive ? '<span class="opt-tag">SELECTED</span>' : ''}`;
            div.addEventListener('click', () => {
                tuningData.currentWheelType = wt.typeIndex;
                tuningData.currentWheelIndex = -1;
                fetch('https://garage/applyWheelType', {
                    method: 'POST',
                    body: JSON.stringify({ wheelType: wt.typeIndex })
                }).then(res => res.json()).then(data => {
                    const wObj = (tuningData.wheels || []).find(w => w.typeIndex === wt.typeIndex);
                    if (wObj && data.count !== undefined) wObj.count = data.count;
                    renderWheels();
                });
            });
            optionsList.appendChild(div);
        });

        // Wheel design options for current type
        const curWheelData = (tuningData.wheels || []).find(w => w.typeIndex === curType);
        if (curWheelData && curWheelData.count > 0) {
            const subHeader2 = document.createElement('div');
            subHeader2.className = 'options-sub-header';
            subHeader2.textContent = 'WHEEL DESIGN';
            optionsList.appendChild(subHeader2);

            addWheelOption('Stock', -1, curIdx === -1);
            for (let i = 0; i < curWheelData.count; i++) {
                addWheelOption(`Design ${i + 1}`, i, curIdx === i);
            }
        }
    }

    function addWheelOption(label, value, isActive) {
        const div = document.createElement('div');
        div.className = 'opt-item' + (isActive ? ' active' : '');
        div.innerHTML = `<span>${label}</span>${isActive ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
        div.addEventListener('click', () => {
            tuningData.currentWheelIndex = value;
            fetch('https://garage/applyWheelIndex', {
                method: 'POST',
                body: JSON.stringify({ wheelIndex: value })
            });
            renderWheels();
        });
        optionsList.appendChild(div);
    }

    // ========================
    // Wheel / rim color
    // ========================

    function renderWheelColor() {
        optionsList.innerHTML = '';
        const curColor = tuningData.currentWheelColor || 0;
        WHEEL_COLORS.forEach(wc => {
            const isActive = wc.idx === curColor;
            const div = document.createElement('div');
            div.className = 'opt-item' + (isActive ? ' active' : '');
            div.innerHTML = `<span style="display:flex;align-items:center;gap:10px"><span style="display:inline-block;width:16px;height:16px;border-radius:50%;background:${wc.hex};border:1px solid rgba(255,255,255,0.2)"></span>${wc.label}</span>${isActive ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
            div.addEventListener('click', () => {
                tuningData.currentWheelColor = wc.idx;
                fetch('https://garage/applyWheelColor', {
                    method: 'POST',
                    body: JSON.stringify({ value: wc.idx })
                });
                renderWheelColor();
            });
            optionsList.appendChild(div);
        });
    }

    // ========================
    // Window tint
    // ========================

    function renderWindowTint() {
        optionsList.innerHTML = '';
        const curTint = tuningData.currentWindowTint || 0;
        (tuningData.tints || []).forEach(t => {
            const isActive = t.index === curTint;
            const div = document.createElement('div');
            div.className = 'opt-item' + (isActive ? ' active' : '');
            div.innerHTML = `<span>${t.label}</span>${isActive ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
            div.addEventListener('click', () => {
                tuningData.currentWindowTint = t.index;
                fetch('https://garage/applyWindowTint', {
                    method: 'POST',
                    body: JSON.stringify({ value: t.index })
                });
                renderWindowTint();
            });
            optionsList.appendChild(div);
        });
    }

    // ========================
    // Livery
    // ========================

    function renderLivery() {
        optionsList.innerHTML = '';
        const curLivery = tuningData.currentLivery || -1;
        const count = tuningData.liveryCount || 0;

        const stockDiv = document.createElement('div');
        stockDiv.className = 'opt-item' + (curLivery === -1 ? ' active' : '');
        stockDiv.innerHTML = `<span>None</span>${curLivery === -1 ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
        stockDiv.addEventListener('click', () => {
            tuningData.currentLivery = -1;
            fetch('https://garage/applyLivery', { method: 'POST', body: JSON.stringify({ value: -1 }) });
            renderLivery();
        });
        optionsList.appendChild(stockDiv);

        for (let i = 0; i < count; i++) {
            const isActive = curLivery === i;
            const div = document.createElement('div');
            div.className = 'opt-item' + (isActive ? ' active' : '');
            div.innerHTML = `<span>Livery ${i + 1}</span>${isActive ? '<span class="opt-tag">EQUIPPED</span>' : ''}`;
            div.addEventListener('click', () => {
                tuningData.currentLivery = i;
                fetch('https://garage/applyLivery', { method: 'POST', body: JSON.stringify({ value: i }) });
                renderLivery();
            });
            optionsList.appendChild(div);
        }
    }

    // ========================
    // Neon underglow
    // ========================

    function renderNeon() {
        optionsList.innerHTML = '';
        const isOn = !!tuningData.neon;
        const nColor = tuningData.neonColor || { r: 0, g: 150, b: 255 };

        // Toggle
        const toggleRow = document.createElement('div');
        toggleRow.className = 'toggle-row';
        toggleRow.innerHTML = `<span>Underglow</span><div class="toggle-switch ${isOn ? 'on' : ''}" id="neonToggle"></div>`;
        toggleRow.querySelector('.toggle-switch').addEventListener('click', () => {
            tuningData.neon = !tuningData.neon;
            fetch('https://garage/applyNeon', {
                method: 'POST',
                body: JSON.stringify({ enabled: tuningData.neon, color: nColor })
            });
            renderNeon();
        });
        optionsList.appendChild(toggleRow);

        if (isOn) {
            const area = document.createElement('div');
            area.className = 'color-picker-area';

            buildHSVPicker(area, nColor, (r, g, b) => {
                nColor.r = r; nColor.g = g; nColor.b = b;
                tuningData.neonColor = nColor;
                fetch('https://garage/applyNeonColor', {
                    method: 'POST',
                    body: JSON.stringify({ r, g, b })
                });
            });

            optionsList.appendChild(area);
        }
    }

    // ========================
    // Turbo
    // ========================

    function renderTurbo() {
        optionsList.innerHTML = '';
        const isOn = !!tuningData.turbo;
        const toggleRow = document.createElement('div');
        toggleRow.className = 'toggle-row';
        toggleRow.innerHTML = `<span>Turbo Upgrade</span><div class="toggle-switch ${isOn ? 'on' : ''}" id="turboToggle"></div>`;
        toggleRow.querySelector('.toggle-switch').addEventListener('click', () => {
            tuningData.turbo = !tuningData.turbo;
            fetch('https://garage/applyTurbo', {
                method: 'POST',
                body: JSON.stringify({ enabled: tuningData.turbo })
            });
            renderTurbo();
        });
        optionsList.appendChild(toggleRow);
    }

    // ========================
    // Extras
    // ========================

    function renderExtras() {
        optionsList.innerHTML = '';
        const extras = tuningData.extras || [];
        extras.forEach(extra => {
            const toggleRow = document.createElement('div');
            toggleRow.className = 'toggle-row';
            toggleRow.innerHTML = `<span>Extra ${extra.id + 1}</span><div class="toggle-switch ${extra.enabled ? 'on' : ''}"></div>`;
            toggleRow.querySelector('.toggle-switch').addEventListener('click', () => {
                extra.enabled = !extra.enabled;
                fetch('https://garage/applyExtra', {
                    method: 'POST',
                    body: JSON.stringify({ id: extra.id, enabled: extra.enabled })
                });
                renderExtras();
            });
            optionsList.appendChild(toggleRow);
        });
    }

    // ========================
    // Doors / Hood / Trunk — floating toolbar
    // ========================

    const DOOR_BTNS = [
        { idx: 4, tip: 'Hood',        icon: 'icon-hood.png',       mirror: false },
        { idx: 5, tip: 'Trunk',       icon: 'icon-trunk.png',      mirror: false },
        { idx: 0, tip: 'Front Left',  icon: 'icon-door-front.png', mirror: false },
        { idx: 1, tip: 'Front Right', icon: 'icon-door-front.png', mirror: true  },
        { idx: 2, tip: 'Rear Left',   icon: 'icon-door-rear.png',  mirror: false },
        { idx: 3, tip: 'Rear Right',  icon: 'icon-door-rear.png',  mirror: true  },
    ];

    let doorToolbar = null;

    function buildDoorToolbar() {
        if (doorToolbar) doorToolbar.remove();
        doorToolbar = document.createElement('div');
        doorToolbar.className = 'door-toolbar';

        DOOR_BTNS.forEach(panel => {
            const btn = document.createElement('button');
            btn.className = 'door-toolbar-btn';
            btn.title = panel.tip;
            const img = document.createElement('img');
            img.src = panel.icon;
            img.draggable = false;
            if (panel.mirror) img.style.transform = 'scaleX(-1)';
            btn.appendChild(img);
            btn.addEventListener('click', () => {
                doorStates[panel.idx] = !doorStates[panel.idx];
                btn.classList.toggle('active', doorStates[panel.idx]);
                fetch('https://garage/toggleDoor', {
                    method: 'POST',
                    body: JSON.stringify({ door: panel.idx, open: doorStates[panel.idx] })
                });
            });
            doorToolbar.appendChild(btn);
        });

        document.body.appendChild(doorToolbar);
    }

    function removeDoorToolbar() {
        if (doorToolbar) { doorToolbar.remove(); doorToolbar = null; }
    }

    // ========================
    // Save / Cancel
    // ========================

    btnSave.addEventListener('click', () => {
        fetch('https://garage/saveTuning', { method: 'POST', body: '{}' });
    });

    btnCancel.addEventListener('click', () => {
        fetch('https://garage/cancelTuning', { method: 'POST', body: '{}' });
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            fetch('https://garage/cancelTuning', { method: 'POST', body: '{}' });
        }
    });

    // ========================
    // Camera orbit via mouse drag on background
    // ========================

    let isDragging = false;
    let lastMouseX = 0;
    let lastMouseY = 0;

    document.addEventListener('mousedown', (e) => {
        // Only drag on the transparent background, not on panels
        if (e.target === document.body || e.target === app) {
            isDragging = true;
            lastMouseX = e.clientX;
            lastMouseY = e.clientY;
            e.preventDefault();
        }
    });

    document.addEventListener('mousemove', (e) => {
        if (!isDragging) return;
        const dx = e.clientX - lastMouseX;
        const dy = e.clientY - lastMouseY;
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
        if (Math.abs(dx) > 0 || Math.abs(dy) > 0) {
            fetch('https://garage/cameraOrbit', {
                method: 'POST',
                body: JSON.stringify({ dx, dy })
            });
        }
    });

    document.addEventListener('mouseup', () => { isDragging = false; });

    document.addEventListener('wheel', (e) => {
        if (e.target.closest('.options-list') || e.target.closest('.category-list')) return;
        fetch('https://garage/cameraZoom', {
            method: 'POST',
            body: JSON.stringify({ delta: e.deltaY > 0 ? 1 : -1 })
        });
        e.preventDefault();
    }, { passive: false });

    // ========================
    // Utilities
    // ========================

    function hexToRgb(hex) {
        const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        return result ? {
            r: parseInt(result[1], 16),
            g: parseInt(result[2], 16),
            b: parseInt(result[3], 16)
        } : { r: 0, g: 0, b: 0 };
    }

    function rgbToHex(r, g, b) {
        return '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
    }

    function rgbToHsv(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        const d = max - min;
        let h = 0, s = max === 0 ? 0 : d / max, v = max;
        if (d !== 0) {
            if (max === r)      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
            else if (max === g) h = ((b - r) / d + 2) / 6;
            else                h = ((r - g) / d + 4) / 6;
        }
        return { h: h * 360, s, v };
    }

    function hsvToRgb(h, s, v) {
        h = ((h % 360) + 360) % 360 / 360;
        const i = Math.floor(h * 6);
        const f = h * 6 - i;
        const p = v * (1 - s);
        const q = v * (1 - f * s);
        const t = v * (1 - (1 - f) * s);
        let r, g, b;
        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }
        return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) };
    }

    // ========================
    // Reusable HSV Picker
    // ========================

    let _hsvPicker = null;

    document.addEventListener('mousemove', (e) => {
        if (!_hsvPicker) return;
        if (_hsvPicker.svDrag)  _hsvPicker.onSV(e);
        if (_hsvPicker.hueDrag) _hsvPicker.onHue(e);
    });
    document.addEventListener('mouseup', () => {
        if (_hsvPicker) { _hsvPicker.svDrag = false; _hsvPicker.hueDrag = false; }
    });

    function buildHSVPicker(parentEl, curRgb, onChange) {
        const SV_W = 272, SV_H = 180, HUE_H = 16;
        let hsv = rgbToHsv(curRgb.r, curRgb.g, curRgb.b);

        const state = { svDrag: false, hueDrag: false, onSV: null, onHue: null };
        _hsvPicker = state;

        // -- SV Canvas --
        const svCanvas = document.createElement('canvas');
        svCanvas.className = 'color-sv-canvas';
        svCanvas.width = SV_W; svCanvas.height = SV_H;
        const svCtx = svCanvas.getContext('2d');

        function drawSV() {
            svCtx.fillStyle = `hsl(${hsv.h}, 100%, 50%)`;
            svCtx.fillRect(0, 0, SV_W, SV_H);
            const wGrad = svCtx.createLinearGradient(0, 0, SV_W, 0);
            wGrad.addColorStop(0, '#fff');
            wGrad.addColorStop(1, 'rgba(255,255,255,0)');
            svCtx.fillStyle = wGrad;
            svCtx.fillRect(0, 0, SV_W, SV_H);
            const bGrad = svCtx.createLinearGradient(0, 0, 0, SV_H);
            bGrad.addColorStop(0, 'rgba(0,0,0,0)');
            bGrad.addColorStop(1, '#000');
            svCtx.fillStyle = bGrad;
            svCtx.fillRect(0, 0, SV_W, SV_H);

            const cx = hsv.s * (SV_W - 1);
            const cy = (1 - hsv.v) * (SV_H - 1);
            svCtx.beginPath(); svCtx.arc(cx, cy, 6, 0, Math.PI * 2);
            svCtx.strokeStyle = '#fff'; svCtx.lineWidth = 2; svCtx.stroke();
            svCtx.beginPath(); svCtx.arc(cx, cy, 7, 0, Math.PI * 2);
            svCtx.strokeStyle = '#000'; svCtx.lineWidth = 1; svCtx.stroke();
        }

        state.onSV = function (e) {
            const rect = svCanvas.getBoundingClientRect();
            hsv.s = Math.max(0, Math.min(1, (e.clientX - rect.left) / (rect.width - 1)));
            hsv.v = Math.max(0, Math.min(1, 1 - (e.clientY - rect.top) / (rect.height - 1)));
            refresh();
        };
        svCanvas.addEventListener('mousedown', (e) => {
            state.svDrag = true; state.onSV(e); e.preventDefault();
        });
        parentEl.appendChild(svCanvas);

        // -- Hue Strip --
        const hueCanvas = document.createElement('canvas');
        hueCanvas.className = 'color-hue-strip';
        hueCanvas.width = SV_W; hueCanvas.height = HUE_H;
        const hueCtx = hueCanvas.getContext('2d');

        function drawHue() {
            const grad = hueCtx.createLinearGradient(0, 0, SV_W, 0);
            for (let i = 0; i <= 6; i++) grad.addColorStop(i / 6, `hsl(${i * 60}, 100%, 50%)`);
            hueCtx.fillStyle = grad;
            hueCtx.fillRect(0, 0, SV_W, HUE_H);
            const hx = (hsv.h / 360) * (SV_W - 1);
            hueCtx.fillStyle = '#fff';
            hueCtx.fillRect(hx - 1, 0, 3, HUE_H);
            hueCtx.strokeStyle = '#000'; hueCtx.lineWidth = 1;
            hueCtx.strokeRect(hx - 2, 0, 5, HUE_H);
        }

        state.onHue = function (e) {
            const rect = hueCanvas.getBoundingClientRect();
            hsv.h = Math.max(0, Math.min(360, ((e.clientX - rect.left) / (rect.width - 1)) * 360));
            refresh();
        };
        hueCanvas.addEventListener('mousedown', (e) => {
            state.hueDrag = true; state.onHue(e); e.preventDefault();
        });
        parentEl.appendChild(hueCanvas);

        // -- Hex input + preview --
        const hexRow = document.createElement('div');
        hexRow.className = 'color-hex-row';
        const hexLabel = document.createElement('label');
        hexLabel.textContent = 'HEX';
        const hexInput = document.createElement('input');
        hexInput.type = 'text';
        hexInput.className = 'color-hex-input';
        hexInput.maxLength = 7;
        const preview = document.createElement('div');
        preview.className = 'color-preview';
        hexRow.appendChild(hexLabel);
        hexRow.appendChild(hexInput);
        hexRow.appendChild(preview);
        parentEl.appendChild(hexRow);

        hexInput.addEventListener('change', () => {
            const parsed = hexToRgb(hexInput.value);
            if (parsed) { hsv = rgbToHsv(parsed.r, parsed.g, parsed.b); refresh(); }
        });

        function refresh() {
            const rgb = hsvToRgb(hsv.h, hsv.s, hsv.v);
            drawSV(); drawHue();
            hexInput.value = rgbToHex(rgb.r, rgb.g, rgb.b);
            preview.style.background = `rgb(${rgb.r},${rgb.g},${rgb.b})`;
            onChange(rgb.r, rgb.g, rgb.b);
        }

        drawSV(); drawHue();
        const initRgb = hsvToRgb(hsv.h, hsv.s, hsv.v);
        hexInput.value = rgbToHex(initRgb.r, initRgb.g, initRgb.b);
        preview.style.background = `rgb(${initRgb.r},${initRgb.g},${initRgb.b})`;
    }
})();
