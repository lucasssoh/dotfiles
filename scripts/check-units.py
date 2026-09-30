#!/usr/bin/env python3
"""check-units.py — keep the cc-pkg-mng 2 manifests (units/) honest.

Checks every units/<layer>/<name>/unit.toml against the repo:
  - known keys only, name and layer match the directory;
  - `requires` names existing units, with no cycle;
  - every source path in [links], [files] and [binaries] exists, and every
    hook `run` script exists and is executable;
  - [links_if] names existing units and lists paths from [links];
  - units/legacy-map.toml covers every config/*/install.sh on disk and names
    only existing units.

  --packages   also ask dnf whether every package name exists in the enabled
               repositories (slower; needs the network or a fresh cache).

Design: docs/design/cc-pkg-mng-2.md.
"""
import os
import pathlib
import subprocess
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
UNITS = ROOT / 'units'
LAYERS = {'core', 'apps', 'configs'}
KEYS = {
    'name', 'layer', 'summary', 'requires', 'optional', 'ask', 'default',
    'packages', 'binaries', 'links', 'links_if', 'files', 'services',
    'questions', 'hooks', 'verify',
}
PACKAGE_KEYS = {'dnf', 'copr', 'repos', 'build'}

errors = []


def err(where, msg):
    errors.append(f'{where}: {msg}')


def load_units():
    units = {}
    for path in sorted(UNITS.glob('*/*/unit.toml')):
        rel = path.relative_to(ROOT)
        try:
            data = tomllib.loads(path.read_text())
        except tomllib.TOMLDecodeError as e:
            err(rel, f'invalid TOML: {e}')
            continue
        layer, name = path.parent.parent.name, path.parent.name
        for key in data.keys() - KEYS:
            err(rel, f'unknown key "{key}"')
        if data.get('name') != name:
            err(rel, f'name is "{data.get("name")}", directory is "{name}"')
        if data.get('layer') != layer or layer not in LAYERS:
            err(rel, f'layer is "{data.get("layer")}", directory is "{layer}"')
        if not data.get('summary'):
            err(rel, 'missing summary')
        for key in data.get('packages', {}).keys() - PACKAGE_KEYS:
            err(rel, f'unknown [packages] key "{key}"')
        units[name] = (rel, data)
    return units


def check_paths(units):
    for rel, data in units.values():
        for table in ('links', 'files'):
            for src in data.get(table, {}):
                if not (ROOT / src).exists():
                    err(rel, f'[{table}] source does not exist: {src}')
        source = data.get('binaries', {}).get('source')
        if source and not (ROOT / source / 'Cargo.toml').exists():
            err(rel, f'[binaries] source has no Cargo.toml: {source}')
        for hook in data.get('hooks', []):
            run = hook.get('run')
            if run is None:
                continue
            script = ROOT / run
            if not script.is_file():
                err(rel, f'hook {hook.get("name")}: run script does not exist: {run}')
            elif not os.access(script, os.X_OK):
                err(rel, f'hook {hook.get("name")}: run script is not executable: {run}')
        for hook in data.get('hooks', []):
            for w in hook.get('watch', []):
                if not (ROOT / w).exists():
                    err(rel, f'hook {hook.get("name")}: watched path does not exist: {w}')
        links = data.get('links', {})
        for unit, paths in data.get('links_if', {}).items():
            if unit not in units:
                err(rel, f'[links_if] names an unknown unit: {unit}')
            for p in paths:
                if p not in links:
                    err(rel, f'[links_if] lists a path absent from [links]: {p}')


def check_requires(units):
    for rel, data in units.values():
        for dep in data.get('requires', []):
            if dep not in units:
                err(rel, f'requires an unknown unit: {dep}')

    state = {}

    def visit(name, chain):
        if state.get(name) == 'done':
            return
        if state.get(name) == 'active':
            err(units[name][0], 'dependency cycle: ' + ' -> '.join(chain + [name]))
            return
        state[name] = 'active'
        for dep in units[name][1].get('requires', []):
            if dep in units:
                visit(dep, chain + [name])
        state[name] = 'done'

    for name in units:
        visit(name, [])


def check_legacy_map(units):
    path = UNITS / 'legacy-map.toml'
    rel = path.relative_to(ROOT)
    data = tomllib.loads(path.read_text())
    mapped = data.get('modules', {})
    on_disk = {
        str(p.parent.relative_to(ROOT / 'config'))
        for p in (ROOT / 'config').glob('*/install.sh')
    } | {
        str(p.parent.relative_to(ROOT / 'config'))
        for p in (ROOT / 'config').glob('*/*/install.sh')
    }
    for module in sorted(on_disk - mapped.keys()):
        err(rel, f'module config/{module} is not mapped')
    for module in sorted(mapped.keys() - on_disk):
        err(rel, f'maps a module that does not exist: {module}')
    for module, targets in list(mapped.items()) + list(data.get('phases', {}).items()):
        for unit in targets:
            if unit not in units:
                err(rel, f'{module} maps to an unknown unit: {unit}')
        if not targets and module not in data.get('dropped', {}):
            err(rel, f'{module} maps to no unit and is not listed under [dropped]')


def _repoquery(*args):
    return set(subprocess.run(
        ['dnf', 'repoquery', '--quiet', '--queryformat', '%{name}\n', *args],
        capture_output=True, text=True,
    ).stdout.split())


def check_packages(units):
    wanted, from_copr = {}, set()
    for rel, data in units.values():
        pk = data.get('packages', {})
        for name in pk.get('dnf', []) + pk.get('build', []):
            wanted.setdefault(name, []).append(data['name'])
            if pk.get('copr'):
                from_copr.add(name)
    if not wanted:
        return
    missing = wanted.keys() - _repoquery(*sorted(wanted))
    # A virtual name (nodejs -> nodejs22, wget -> wget2-wget) is fine for dnf.
    missing = {n for n in missing if not _repoquery('--whatprovides', n)}
    for name in sorted(missing):
        where = ', '.join(wanted[name])
        if name in from_copr:
            print(f'packages: "{name}" not in the enabled repositories; its unit ({where}) '
                  'declares a COPR that is not enabled here — not checked')
        else:
            err('packages', f'"{name}" not found in the enabled repositories (units: {where})')


def main():
    units = load_units()
    check_paths(units)
    check_requires(units)
    check_legacy_map(units)
    if '--packages' in sys.argv[1:]:
        check_packages(units)
    for e in errors:
        print(e)
    print(f'{len(units)} units, {len(errors)} problem(s)')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
