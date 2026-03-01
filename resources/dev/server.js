const fs = require('fs');
const path = require('path');

const RESOURCES_DIR = path.resolve(GetResourcePath(GetCurrentResourceName()), '..');

// Resources that should never be auto-restarted
const IGNORE = new Set(['dev', 'oxmysql', 'hardcap', 'sessionmanager', 'spawnmanager']);

const WATCH_EXTENSIONS = new Set(['.lua', '.js', '.html', '.css', '.json']);

// Debounce timers per resource so rapid saves don't spam restarts
const pending = new Map();
const DEBOUNCE_MS = 500;

function restartResource(name) {
    if (IGNORE.has(name)) return;
    console.log(`^3[dev]^0 Restarting ^5${name}^0 ...`);
    ExecuteCommand(`ensure ${name}`);
}

// --- File watcher ----------------------------------------------------------

function watchResource(resourceName, dir) {
    try {
        fs.watch(dir, { recursive: true }, (_event, filename) => {
            if (!filename) return;
            const ext = path.extname(filename).toLowerCase();
            if (!WATCH_EXTENSIONS.has(ext)) return;

            if (pending.has(resourceName)) clearTimeout(pending.get(resourceName));
            pending.set(resourceName, setTimeout(() => {
                pending.delete(resourceName);
                restartResource(resourceName);
            }, DEBOUNCE_MS));
        });
    } catch (e) {
        // Resource directory may not be watchable (e.g. network drive)
    }
}

function startWatching() {
    let dirs;
    try {
        dirs = fs.readdirSync(RESOURCES_DIR);
    } catch { return; }

    for (const entry of dirs) {
        if (IGNORE.has(entry)) continue;
        const full = path.join(RESOURCES_DIR, entry);
        try {
            if (!fs.statSync(full).isDirectory()) continue;
        } catch { continue; }
        watchResource(entry, full);
    }

    console.log(`^2[dev]^0 Watching ${dirs.length} resources for changes — save a file to hot-reload`);
}

startWatching();

// --- Manual /refresh command -----------------------------------------------

RegisterCommand('refresh_resource', (source, args) => {
    // Only allow from server console (source 0) or add ace perms for players
    if (source !== 0) {
        console.log(`^1[dev]^0 /refresh_resource can only be used from the server console`);
        return;
    }
    const name = args[0];
    if (!name) {
        console.log('^3[dev]^0 Usage: refresh_resource <name>  |  refresh_resource all');
        return;
    }
    if (name === 'all') {
        let dirs;
        try { dirs = fs.readdirSync(RESOURCES_DIR); } catch { return; }
        for (const entry of dirs) {
            if (IGNORE.has(entry)) continue;
            const full = path.join(RESOURCES_DIR, entry);
            try { if (!fs.statSync(full).isDirectory()) continue; } catch { continue; }
            ExecuteCommand(`ensure ${entry}`);
        }
        console.log('^2[dev]^0 All resources restarted');
    } else {
        ExecuteCommand(`ensure ${name}`);
        console.log(`^2[dev]^0 Restarted ^5${name}^0`);
    }
}, true);
