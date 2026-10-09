#!/usr/bin/env python3
"""
The python examples have no undefined names and no mixed up exception names.

An error path only runs when something goes wrong, so a typo there stays hidden
until the day it matters, and then the real message is replaced by a traceback:

- a name that is defined nowhere it can be reached (writelog for writeLog,
  stURL for stUrl);
- an `except ... as et:` whose body uses `e`, or the other way round.

ast.parse, which the hygiene check uses, accepts both. This reads the scopes with
the symtable module, so a name defined in another function does not count.

Runs offline. Exit code 0 means clean.
"""
import ast
import builtins
import glob
import os
import re
import symtable
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ALWAYS = set(dir(builtins)) | {"__file__", "__name__", "__doc__"}

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %s" % (got,)))
    failed += 0 if ok else 1


def undefined_names(source, filename="<source>"):
    """Names used in a scope that neither the scope, an enclosing one, the module nor the builtins define."""
    top = symtable.symtable(source, filename, "exec")
    module_defined = {s.get_name() for s in top.get_symbols()
                      if s.is_assigned() or s.is_imported() or s.is_namespace() or s.is_parameter()}
    # a function that says "global x" and assigns it defines x for the whole module
    def assigned_globals(table):
        names = {s.get_name() for s in table.get_symbols() if s.is_declared_global() and s.is_assigned()}
        for child in table.get_children():
            names |= assigned_globals(child)
        return names

    module_defined |= assigned_globals(top)
    found = set()

    def walk(table):
        for sym in table.get_symbols():
            name = sym.get_name()
            if not sym.is_referenced() or name in ALWAYS:
                continue
            if table.get_type() == "module":
                defined = name in module_defined
            else:
                defined = (not sym.is_global()) or name in module_defined
            if not defined:
                found.add(name)
        for child in table.get_children():
            walk(child)

    walk(top)
    return sorted(found)


def mixed_up_exception_names(source):
    """(line, bound, used) for an except handler whose body uses another handler's name."""
    tree = ast.parse(source)
    handlers = [n for n in ast.walk(tree) if isinstance(n, ast.ExceptHandler) and n.name]
    names = {h.name for h in handlers}
    out = []
    for h in handlers:
        assigned = {n.id for b in h.body for n in ast.walk(b) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)}
        for b in h.body:
            for n in ast.walk(b):
                if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load) and n.id in names and n.id != h.name and n.id not in assigned:
                    out.append((n.lineno, h.name, n.id))
    return out


print("=== the check itself finds what it is for ===")
check("a misspelled function name is found",
      undefined_names("def writeLog(s):\n    pass\n\ndef f():\n    writelog('x')\n") == ["writelog"])
check("a misspelled module level name is found", undefined_names("stUrl = 1\nprint(stURL)\n") == ["stURL"])
check("a name defined in another function does not count",
      undefined_names("def a():\n    helper = 1\n\ndef b():\n    return helper\n") == ["helper"])
check("module names, parameters, imports and builtins are fine",
      undefined_names("import os\nX = 1\n\ndef f(p):\n    return len(os.sep + p) + X\n") == [])
check("a global assigned inside a function is defined",
      undefined_names("def login():\n    global token\n    token = 1\n\ndef use():\n    return token\n") == [])
check("a name bound in the main block is fine for a function",
      undefined_names("def f():\n    return sys.argv\n\nif __name__ == '__main__':\n    import sys\n    f()\n") == [])
check("a handler body using another handler's name is found",
      mixed_up_exception_names("try:\n    pass\nexcept A as et:\n    print(e)\nexcept B as e:\n    pass\n") == [(4, "et", "e")])
check("a writeLog of a bare exception object is found",
      bool(re.search(r"writeLog\((ec|eh|et|ee|e)\s*,", "        writeLog(ec, 'FATAL')")))
check("a handler using its own name is fine",
      mixed_up_exception_names("try:\n    pass\nexcept A as et:\n    print(et)\nexcept B as e:\n    print(e)\n") == [])

print("=== the python examples ===")
files = sorted(glob.glob(os.path.join(REPO, "Admin", "API 2.0", "python", "**", "*.py"), recursive=True)
               + glob.glob(os.path.join(REPO, "tools", "*.py")))
check("there are python examples to read", len(files) > 20, len(files))
for path in files:
    rel = os.path.relpath(path, REPO)
    source = open(path).read()
    check("%s: every name is defined" % rel, not undefined_names(source, rel), undefined_names(source, rel))
    check("%s: every except body uses its own name" % rel, not mixed_up_exception_names(source), mixed_up_exception_names(source))
    bare = [i + 1 for i, line in enumerate(source.split("\n")) if re.search(r"writeLog\((ec|eh|et|ee|e)\s*,", line)]
    check("%s: writeLog is given text, not an exception object" % rel, not bare, bare)

print("=== the integration checks and their library ===")
# They only run against a server, so a name that is wrong on a path the lab does not take (a failure message, a clean-up)
# is found here or not at all, and a refactor of the shared helpers touches all of them
harness_files = sorted(glob.glob(os.path.join(REPO, "tests", "integration", "checks", "*.py"))
                       + glob.glob(os.path.join(REPO, "tests", "integration", "lib", "*.py")))
check("there are integration checks to read", len(harness_files) > 60, len(harness_files))
for path in harness_files:
    rel = os.path.relpath(path, REPO)
    source = open(path).read()
    check("%s: every name is defined" % rel, not undefined_names(source, rel), undefined_names(source, rel))
    check("%s: every except body uses its own name" % rel, not mixed_up_exception_names(source), mixed_up_exception_names(source))

print()
if failed:
    print("test_python_names: FAIL (%d)" % failed)
    sys.exit(1)
print("test_python_names: PASS")
