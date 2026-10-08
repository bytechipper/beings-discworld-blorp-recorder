"""Run with python3 -m unittest discover -s tests -v (requires liblua 5.4)."""
import ctypes
import ctypes.util
from pathlib import Path
import os
import unittest
import subprocess
import tempfile
import tomllib
import zipfile
import sqlite3
import json
import re

ROOT = Path(__file__).resolve().parent.parent

class Lua:
    def __init__(self):
        self.lib = ctypes.CDLL(ctypes.util.find_library('lua5.4'))
        for name, args, result in [
            ('luaL_newstate', [], ctypes.c_void_p),
            ('luaL_openlibs', [ctypes.c_void_p], None),
            ('luaL_loadstring', [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_int),
            ('lua_pcallk', [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p], ctypes.c_int),
            ('lua_tolstring', [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p], ctypes.c_char_p),
            ('lua_close', [ctypes.c_void_p], None),
        ]:
            fn = getattr(self.lib, name); fn.argtypes = args; fn.restype = result
        self.state = self.lib.luaL_newstate()
        self.lib.luaL_openlibs(self.state)

    def database(self):
        lib = self.lib
        state = self.state
        self.connection = sqlite3.connect(':memory:')
        self.connection.row_factory = sqlite3.Row
        for name, args, result in [
            ('lua_gettop', [ctypes.c_void_p], ctypes.c_int),
            ('lua_type', [ctypes.c_void_p, ctypes.c_int], ctypes.c_int),
            ('lua_tonumberx', [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p], ctypes.c_double),
            ('lua_rawgeti', [ctypes.c_void_p, ctypes.c_int, ctypes.c_longlong], ctypes.c_int),
            ('lua_settop', [ctypes.c_void_p, ctypes.c_int], None),
            ('lua_pushstring', [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_void_p),
            ('lua_pushcclosure', [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int], None),
            ('lua_setglobal', [ctypes.c_void_p, ctypes.c_char_p], None),
        ]:
            fn = getattr(lib, name); fn.argtypes = args; fn.restype = result
        def sql_callback(state):
            try:
                query = lib.lua_tolstring(state, 1, None).decode()
                params = []
                if lib.lua_gettop(state) >= 2 and lib.lua_type(state, 2) == 5:
                    for i in range(1, 100):
                        kind = lib.lua_rawgeti(state, 2, i)
                        if kind == 0:
                            lib.lua_settop(state, -2)
                            break
                        value = lib.lua_tolstring(state, -1, None)
                        params.append(lib.lua_tonumberx(state, -1, None) if kind == 3 else value.decode() if value else None)
                        lib.lua_settop(state, -2)
                cursor = self.connection.execute(query, params)
                rows = [dict(row) for row in cursor.fetchall()] if cursor.description else []
                def lua_value(v):
                    if v is None: return 'nil'
                    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
                    return str(v)
                result = '{' + ','.join('{' + ','.join('['+lua_value(k)+']='+lua_value(v) for k,v in row.items()) + '}' for row in rows) + '}'
                lib.luaL_loadstring(state, ('return ' + result).encode())
                status = lib.lua_pcallk(state, 0, 1, 0, 0, None)
                if status: raise RuntimeError(lib.lua_tolstring(state, -1, None).decode())
                return 1
            except Exception as error:
                lib.lua_pushstring(state, str(error).encode())
                return 1
        self.callback = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(sql_callback)
        lib.lua_pushcclosure(state, self.callback, 0)
        lib.lua_setglobal(state, b'_sql')

    def run(self, code):
        try:
            status = self.lib.luaL_loadstring(self.state, code.encode())
            if not status:
                status = self.lib.lua_pcallk(self.state, 0, 0, 0, 0, None)
            if status:
                raise AssertionError(self.lib.lua_tolstring(self.state, -1, None).decode())
        finally:
            self.lib.lua_close(self.state)


import sys
SCENARIO = 'dofile("tests/recorder_test.lua")'

class PluginTests(unittest.TestCase):
    def test_lua_syntax(self):
        for path in (ROOT / 'src').glob('*.lua'):
            with self.subTest(path=path):
                Lua().run(f'assert(loadfile({str(path)!r}))')

    def test_clean_reproducible_package(self):
        manifest = tomllib.loads((ROOT / 'plugin.toml').read_text())
        self.assertEqual(manifest['mallard_api_version'], '1.0')
        self.assertEqual(manifest['minimum_app_version'], '0.27.0')
        with tempfile.TemporaryDirectory() as directory:
            a, b = [Path(directory) / n for n in ('a.mallardx', 'b.mallardx')]
            for output in (a, b):
                subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), str(output)], check=True, capture_output=True)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with zipfile.ZipFile(a) as archive:
                names = archive.namelist()
                self.assertEqual(len(names), len(set(names)))
                self.assertIn('plugin.toml', names)
                self.assertIn('README.md', names)
                for name in names:
                    self.assertTrue(name in ('plugin.toml', 'LICENSE', 'README.md') or name.startswith(('src/', 'ui/', 'assets/')), name)
                    self.assertNotIn('..', Path(name).parts)
                    self.assertEqual(archive.read(name), (ROOT / name).read_bytes())
                self.assertIn(manifest['entry'], names)
                for panel in manifest.get('panels', {}).values(): self.assertIn(panel['entry'], names)

    def test_permissions(self):
        manifest = tomllib.loads((ROOT / 'plugin.toml').read_text())
        permissions = manifest['permissions']
        source = '\n'.join(path.read_text() for path in (ROOT / 'src').glob('*.lua'))
        if re.search(r'mud\.send(?:_raw)?\s*\(', source): self.assertTrue(permissions['sends'])
        if re.search(r'db\.(?:query|exec|transaction)\s*\(', source): self.assertTrue(permissions.get('database'))
        for package in re.findall(r'gmcp\.on\("([^"\n]+)"', source):
            self.assertIn(package, permissions.get('gmcp_access', []))
        self.assertFalse(permissions.get('network'))

    def test_runtime_behavior(self):
        previous = Path.cwd()
        try:
            os.chdir(ROOT)
            lua = Lua()
            lua.database()
            lua.run(SCENARIO)
        finally:
            os.chdir(previous)

if __name__ == '__main__':
    unittest.main()
