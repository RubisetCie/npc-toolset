#!/usr/bin/env python3
"""Run the Lua regression suite using an interpreter or liblua (no pip packages)."""
from __future__ import annotations

import ctypes
import ctypes.util
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    for name in ("luajit", "lua5.1", "lua", "lua5.4", "lua5.3"):
        executable = shutil.which(name)
        if executable:
            return subprocess.run([executable, "tests/run.lua"], check=False).returncode

    # Some systems ship the Lua shared library without the command-line binary.
    library = next((path for name in ("lua5.4", "lua5.3")
                    if (path := ctypes.util.find_library(name))), None)
    if not library:
        print("Install Lua/LuaJIT, then run: python3 tests/run.py", file=sys.stderr)
        return 2
    lua = ctypes.CDLL(library)
    state_type = ctypes.c_void_p
    lua.luaL_newstate.argtypes = []
    lua.luaL_newstate.restype = state_type
    lua.luaL_openlibs.argtypes = [state_type]
    lua.luaL_openlibs.restype = None
    lua.luaL_loadfilex.argtypes = [state_type, ctypes.c_char_p, ctypes.c_char_p]
    lua.luaL_loadfilex.restype = ctypes.c_int
    lua.lua_pcallk.argtypes = [state_type, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                              ctypes.c_ssize_t, ctypes.c_void_p]
    lua.lua_pcallk.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [state_type, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [state_type]
    lua.lua_close.restype = None
    state = lua.luaL_newstate()
    if not state:
        raise MemoryError("Unable to create Lua state")
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadfilex(state, b"tests/run.lua", None)
        if status == 0:
            status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            message = lua.lua_tolstring(state, -1, None)
            print(message.decode("utf-8", errors="replace") if message else "Lua error",
                  file=sys.stderr)
        return 1 if status else 0
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    raise SystemExit(main())
