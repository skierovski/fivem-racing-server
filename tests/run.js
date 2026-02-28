const fengari = require('fengari');
const { lua, lauxlib, lualib } = fengari;
const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
let totalTests = 0;
let passed = 0;
let failed = 0;
const failures = [];

function toLuaString(str) {
    return fengari.to_luastring(str);
}

function toJsString(L, idx) {
    return fengari.to_jsstring(lua.lua_tostring(L, idx));
}

function runTestFile(filePath) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);

    const fileName = path.relative(projectRoot, filePath);
    const projRoot = projectRoot.replace(/\\/g, '/');

    // Custom require that resolves from project root
    const requireShim = `
        local _orig_require = require
        package.path = '${projRoot}/?.lua;${projRoot}/?/init.lua;' .. package.path
        function require(modname)
            local modpath = modname:gsub('%.', '/')
            local fullpath = '${projRoot}/' .. modpath .. '.lua'
            local f, err = loadfile(fullpath)
            if f then return f() end
            return _orig_require(modname)
        end
    `;

    let status = lauxlib.luaL_dostring(L, toLuaString(requireShim));
    if (status !== lua.LUA_OK) {
        const err = toJsString(L, -1);
        console.error(`  SETUP ERROR: ${err}`);
        return;
    }

    // Inject test framework
    const testFramework = `
        _TESTS = {}
        _CURRENT_SUITE = ''

        function describe(name, fn)
            _CURRENT_SUITE = name
            fn()
            _CURRENT_SUITE = ''
        end

        function it(name, fn)
            table.insert(_TESTS, {
                suite = _CURRENT_SUITE,
                name = name,
                fn = fn,
            })
        end

        function expect(val)
            return {
                toBe = function(expected)
                    if val ~= expected then
                        error('Expected ' .. tostring(expected) .. ' but got ' .. tostring(val), 2)
                    end
                end,
                toEqual = function(expected)
                    if val ~= expected then
                        error('Expected ' .. tostring(expected) .. ' but got ' .. tostring(val), 2)
                    end
                end,
                toBeGreaterThan = function(expected)
                    if not (val > expected) then
                        error('Expected ' .. tostring(val) .. ' > ' .. tostring(expected), 2)
                    end
                end,
                toBeLessThan = function(expected)
                    if not (val < expected) then
                        error('Expected ' .. tostring(val) .. ' < ' .. tostring(expected), 2)
                    end
                end,
                toBeGreaterThanOrEqual = function(expected)
                    if not (val >= expected) then
                        error('Expected ' .. tostring(val) .. ' >= ' .. tostring(expected), 2)
                    end
                end,
                toBeLessThanOrEqual = function(expected)
                    if not (val <= expected) then
                        error('Expected ' .. tostring(val) .. ' <= ' .. tostring(expected), 2)
                    end
                end,
                toBeNil = function()
                    if val ~= nil then
                        error('Expected nil but got ' .. tostring(val), 2)
                    end
                end,
                toNotBeNil = function()
                    if val == nil then
                        error('Expected non-nil value', 2)
                    end
                end,
                toBeTrue = function()
                    if val ~= true then
                        error('Expected true but got ' .. tostring(val), 2)
                    end
                end,
                toBeFalse = function()
                    if val ~= false then
                        error('Expected false but got ' .. tostring(val), 2)
                    end
                end,
                toBeCloseTo = function(expected, precision)
                    precision = precision or 0.01
                    if math.abs(val - expected) > precision then
                        error('Expected ~' .. tostring(expected) .. ' but got ' .. tostring(val) .. ' (precision: ' .. tostring(precision) .. ')', 2)
                    end
                end,
                toHaveLength = function(expected)
                    local len = #val
                    if len ~= expected then
                        error('Expected length ' .. tostring(expected) .. ' but got ' .. tostring(len), 2)
                    end
                end,
            }
        end
    `;

    status = lauxlib.luaL_dostring(L, toLuaString(testFramework));
    if (status !== lua.LUA_OK) {
        const err = toJsString(L, -1);
        console.error(`  FRAMEWORK ERROR: ${err}`);
        return;
    }

    // Load the test file via loadfile (handles file paths properly)
    status = lauxlib.luaL_loadfile(L, toLuaString(filePath));
    if (status !== lua.LUA_OK) {
        const err = toJsString(L, -1);
        console.error(`  LOAD ERROR in ${fileName}: ${err}`);
        failed++;
        failures.push({ file: fileName, test: '(file load)', error: err });
        return;
    }

    status = lua.lua_pcall(L, 0, 0, 0);
    if (status !== lua.LUA_OK) {
        const err = toJsString(L, -1);
        console.error(`  EXEC ERROR in ${fileName}: ${err}`);
        failed++;
        failures.push({ file: fileName, test: '(exec)', error: err });
        return;
    }

    // Run collected tests
    const runTestsCode = `
        local _results = {}
        for _, test in ipairs(_TESTS) do
            local ok, err = pcall(test.fn)
            table.insert(_results, {
                suite = test.suite,
                name = test.name,
                passed = ok,
                err = ok and '' or tostring(err),
            })
        end
        return _results
    `;

    status = lauxlib.luaL_dostring(L, toLuaString(runTestsCode));
    if (status !== lua.LUA_OK) {
        const err = toJsString(L, -1);
        console.error(`  RUN ERROR: ${err}`);
        return;
    }

    // Read results
    const resultsIdx = lua.lua_gettop(L);
    if (!lua.lua_istable(L, resultsIdx)) {
        console.error('  ERROR: test runner did not return a table');
        return;
    }

    const numResults = lauxlib.luaL_len(L, resultsIdx);
    let lastSuite = '';

    for (let i = 1; i <= numResults; i++) {
        lua.lua_rawgeti(L, resultsIdx, i);
        const tblIdx = lua.lua_gettop(L);

        lua.lua_getfield(L, tblIdx, toLuaString('suite'));
        const suite = lua.lua_isstring(L, -1) ? toJsString(L, -1) : '';
        lua.lua_pop(L, 1);

        lua.lua_getfield(L, tblIdx, toLuaString('name'));
        const name = lua.lua_isstring(L, -1) ? toJsString(L, -1) : '';
        lua.lua_pop(L, 1);

        lua.lua_getfield(L, tblIdx, toLuaString('passed'));
        const ok = lua.lua_toboolean(L, -1);
        lua.lua_pop(L, 1);

        lua.lua_getfield(L, tblIdx, toLuaString('err'));
        const err = lua.lua_isstring(L, -1) ? toJsString(L, -1) : '';
        lua.lua_pop(L, 1);

        lua.lua_pop(L, 1);

        totalTests++;
        if (suite !== lastSuite) {
            console.log(`\n  ${suite}`);
            lastSuite = suite;
        }

        if (ok) {
            passed++;
            console.log(`    PASS  ${name}`);
        } else {
            failed++;
            console.log(`    FAIL  ${name}`);
            console.log(`          ${err}`);
            failures.push({ file: fileName, test: `${suite} > ${name}`, error: err });
        }
    }
}

// Main
console.log('========================================');
console.log(' BlackList Racing - Test Suite');
console.log('========================================');

const testsDir = path.join(projectRoot, 'tests');
const testFiles = fs.readdirSync(testsDir)
    .filter(f => f.endsWith('_spec.lua'))
    .sort();

for (const file of testFiles) {
    const filePath = path.join(testsDir, file);
    console.log(`\n--- ${file} ---`);
    runTestFile(filePath);
}

console.log('\n========================================');
console.log(` Results: ${passed} passed, ${failed} failed, ${totalTests} total`);
console.log('========================================');

if (failures.length > 0) {
    console.log('\nFailures:');
    for (const f of failures) {
        console.log(`  ${f.file} > ${f.test}`);
        console.log(`    ${f.error}`);
    }
}

process.exit(failed > 0 ? 1 : 0);
