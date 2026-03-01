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

    const COLOR_PRESETS = [
        '#1a1a1a', '#333333', '#666666', '#999999', '#cccccc', '#ffffff', '#ff0000', '#cc0000',
        '#990000', '#ff4444', '#ff6600', '#ff9900', '#ffcc00', '#ffff00', '#ccff00', '#66ff00',
        '#00ff00', '#00ff66', '#00ffcc', '#00ffff', '#00ccff', '#0099ff', '#0066ff', '#0033ff',
        '#0000ff', '#3300ff', '#6600ff', '#9900ff', '#cc00ff', '#ff00ff', '#ff0099', '#ff0066',
        '#8b4513', '#a0522d', '#cd853f', '#d2691e', '#deb887', '#f5deb3', '#2f4f4f', '#556b2f',
        '#808000', '#483d8b', '#191970', '#000080', '#4b0082', '#800080', '#c71585', '#dc143c',
        '#b22222', '#8b0000', '#ff1493', '#ff69b4', '#ffc0cb', '#f0e68c', '#e6e6fa', '#708090',
    ];

    const CATEGORY_ICONS = {
        color1: '\u{1F3A8}', color2: '\u{1F3A8}',
        spoiler: '\u{1F3CE}', frontBumper: '\u{1F698}', rearBumper: '\u{1F698}',
        sideSkirts: '\u{1F3CE}', hood: '\u{1F3CE}',
        wheels: '\u{2699}', wheelColor: '\u{1F3A8}',
        livery: '\u{1F3AD}', windowTint: '\u{1F576}',
        neon: '\u{1F4A1}', turbo: '\u{26A1}',
        engine: '\u{1F527}', brakes: '\u{1F6D1}', transmission: '\u{2699}', suspension: '\u{1F4CF}',
    };

    const WHEEL_COLORS = [
        // Metallic
        { idx: 0, label: 'Metallic Black', hex: '#0d1116' },
        { idx: 1, label: 'Metallic Graphite', hex: '#1c1d21' },
        { idx: 2, label: 'Metallic Black Steel', hex: '#32383d' },
        { idx: 3, label: 'Metallic Dark Steel', hex: '#454b4f' },
        { idx: 4, label: 'Metallic Silver', hex: '#999da0' },
        { idx: 5, label: 'Metallic Blue Silver', hex: '#c2c4c6' },
        { idx: 111, label: 'Ice White', hex: '#f0f0f0' },
        { idx: 27, label: 'Metallic Red', hex: '#c00e1a' },
        { idx: 29, label: 'Formula Red', hex: '#b6111b' },
        { idx: 35, label: 'Candy Red', hex: '#8f1f21' },
        { idx: 143, label: 'Wine Red', hex: '#5c0a15' },
        { idx: 150, label: 'Lava Red', hex: '#d44217' },
        { idx: 36, label: 'Sunrise Orange', hex: '#d46a17' },
        { idx: 38, label: 'Metallic Orange', hex: '#f78616' },
        { idx: 138, label: 'Bright Orange', hex: '#ff6600' },
        { idx: 88, label: 'Metallic Yellow', hex: '#daaf0f' },
        { idx: 89, label: 'Race Yellow', hex: '#edef00' },
        { idx: 92, label: 'Lime Green', hex: '#9aef00' },
        { idx: 49, label: 'Dark Green', hex: '#0a4c28' },
        { idx: 50, label: 'Racing Green', hex: '#1b6a3c' },
        { idx: 53, label: 'Bright Green', hex: '#00ff44' },
        { idx: 61, label: 'Galaxy Blue', hex: '#091c5e' },
        { idx: 62, label: 'Dark Blue', hex: '#0c0d18' },
        { idx: 64, label: 'Metallic Blue', hex: '#2354a1' },
        { idx: 70, label: 'Ultra Blue', hex: '#1b1fc7' },
        { idx: 141, label: 'Midnight Blue', hex: '#0c0c3b' },
        { idx: 71, label: 'Schafter Purple', hex: '#4a0654' },
        { idx: 145, label: 'Bright Purple', hex: '#6b1f7b' },
        { idx: 142, label: 'Midnight Purple', hex: '#1f0038' },
        { idx: 135, label: 'Hot Pink', hex: '#ff3399' },
        { idx: 90, label: 'Bronze', hex: '#6b5840' },
        { idx: 158, label: 'Pure Gold', hex: '#c2a557' },
        { idx: 117, label: 'Brushed Steel', hex: '#8c8c8c' },
        // Matte
        { idx: 12, label: 'Matte Black', hex: '#151515' },
        { idx: 13, label: 'Matte Gray', hex: '#3b3b3b' },
        { idx: 131, label: 'Matte White', hex: '#e8e8e8' },
        { idx: 39, label: 'Matte Red', hex: '#800000' },
        { idx: 41, label: 'Matte Orange', hex: '#b04500' },
        { idx: 42, label: 'Matte Yellow', hex: '#c4a000' },
        { idx: 55, label: 'Matte Lime', hex: '#418c1e' },
        { idx: 128, label: 'Matte Green', hex: '#2d5a26' },
        { idx: 82, label: 'Matte Dark Blue', hex: '#1a3060' },
        { idx: 83, label: 'Matte Blue', hex: '#253aa7' },
    ];

    // ========================
    // Message handler
    // ========================

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (data.action === 'openTuning') {
            tuningData = data;
            activeCategory = null;
            buildCategories();
            app.classList.remove('hidden');
            optionsPanel.classList.add('hidden');
        } else if (data.action === 'closeTuning') {
            app.classList.add('hidden');
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

    function renderColorPicker(target) {
        optionsList.innerHTML = '';
        const area = document.createElement('div');
        area.className = 'color-picker-area';

        const key = target === 'color1' ? 'primary' : 'secondary';
        const cur = tuningData.currentColors[key] || { r: 0, g: 0, b: 0 };

        // Swatches
        const swatches = document.createElement('div');
        swatches.className = 'color-swatches';
        COLOR_PRESETS.forEach(hex => {
            const s = document.createElement('div');
            s.className = 'color-swatch';
            s.style.background = hex;
            const rgb = hexToRgb(hex);
            if (rgb.r === cur.r && rgb.g === cur.g && rgb.b === cur.b) {
                s.classList.add('active');
            }
            s.addEventListener('click', () => {
                applyColor(target, rgb.r, rgb.g, rgb.b);
                cur.r = rgb.r; cur.g = rgb.g; cur.b = rgb.b;
                renderColorPicker(target);
            });
            swatches.appendChild(s);
        });
        area.appendChild(swatches);

        // RGB sliders
        const sliders = document.createElement('div');
        sliders.className = 'color-sliders';
        ['R', 'G', 'B'].forEach(ch => {
            const val = ch === 'R' ? cur.r : ch === 'G' ? cur.g : cur.b;
            const row = document.createElement('div');
            row.className = 'color-slider-row';
            row.innerHTML = `<label>${ch}</label><input type="range" min="0" max="255" value="${val}"><span class="color-val">${val}</span>`;
            const slider = row.querySelector('input');
            const display = row.querySelector('.color-val');
            slider.addEventListener('input', () => {
                display.textContent = slider.value;
                if (ch === 'R') cur.r = parseInt(slider.value);
                else if (ch === 'G') cur.g = parseInt(slider.value);
                else cur.b = parseInt(slider.value);
                preview.style.background = `rgb(${cur.r},${cur.g},${cur.b})`;
                applyColor(target, cur.r, cur.g, cur.b);
                swatches.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('active'));
            });
            sliders.appendChild(row);
        });
        area.appendChild(sliders);

        // Preview bar
        const preview = document.createElement('div');
        preview.className = 'color-preview';
        preview.style.background = `rgb(${cur.r},${cur.g},${cur.b})`;
        area.appendChild(preview);

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
            // Color swatches for neon
            const area = document.createElement('div');
            area.className = 'color-picker-area';

            const swatches = document.createElement('div');
            swatches.className = 'color-swatches';
            COLOR_PRESETS.forEach(hex => {
                const s = document.createElement('div');
                s.className = 'color-swatch';
                s.style.background = hex;
                const rgb = hexToRgb(hex);
                if (rgb.r === nColor.r && rgb.g === nColor.g && rgb.b === nColor.b) {
                    s.classList.add('active');
                }
                s.addEventListener('click', () => {
                    nColor.r = rgb.r; nColor.g = rgb.g; nColor.b = rgb.b;
                    tuningData.neonColor = nColor;
                    fetch('https://garage/applyNeonColor', {
                        method: 'POST',
                        body: JSON.stringify({ r: rgb.r, g: rgb.g, b: rgb.b })
                    });
                    renderNeon();
                });
                swatches.appendChild(s);
            });
            area.appendChild(swatches);

            // RGB sliders
            const sliders = document.createElement('div');
            sliders.className = 'color-sliders';
            ['R', 'G', 'B'].forEach(ch => {
                const val = ch === 'R' ? nColor.r : ch === 'G' ? nColor.g : nColor.b;
                const row = document.createElement('div');
                row.className = 'color-slider-row';
                row.innerHTML = `<label>${ch}</label><input type="range" min="0" max="255" value="${val}"><span class="color-val">${val}</span>`;
                const slider = row.querySelector('input');
                const display = row.querySelector('.color-val');
                slider.addEventListener('input', () => {
                    display.textContent = slider.value;
                    if (ch === 'R') nColor.r = parseInt(slider.value);
                    else if (ch === 'G') nColor.g = parseInt(slider.value);
                    else nColor.b = parseInt(slider.value);
                    tuningData.neonColor = nColor;
                    preview.style.background = `rgb(${nColor.r},${nColor.g},${nColor.b})`;
                    fetch('https://garage/applyNeonColor', {
                        method: 'POST',
                        body: JSON.stringify({ r: nColor.r, g: nColor.g, b: nColor.b })
                    });
                    swatches.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('active'));
                });
                sliders.appendChild(row);
            });
            area.appendChild(sliders);

            const preview = document.createElement('div');
            preview.className = 'color-preview';
            preview.style.background = `rgb(${nColor.r},${nColor.g},${nColor.b})`;
            area.appendChild(preview);

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
})();
