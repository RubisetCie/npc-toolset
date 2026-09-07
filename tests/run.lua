local passed, failed = 0, 0
M = dofile("tests/mocks.lua")
function test(name, callback)
    local ok, message = xpcall(callback, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n" .. tostring(message))
    end
end
function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local suites = {
    "catalogs",
    "playback",
    "delay",
    "reload",
    "network",
    "paths",
    "ui",
    "discovery"
}
for _, suite in ipairs(suites) do
    local path = "tests/test_" .. suite .. ".lua"
    local file = io.open(path, "r")
    if file then file:close(); dofile(path) end
end
print(string.format("\n%d passed; %d failed (%s, mocked GMod APIs)", passed, failed, _VERSION))
assert(failed == 0, "regression suite failed")
