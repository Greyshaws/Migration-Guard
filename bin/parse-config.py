#!/usr/bin/env python3
"""Parse upgrade-guard TOML config and emit shell variable assignments."""
import sys
import re

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib  # third-party for 3.10 and below
    except ImportError:
        # Minimal pure-Python TOML reader for our config shape only.
        # This is NOT a general TOML parser — it handles only what
        # upgrade-guard.toml uses (sections, key=value, simple arrays).
        tomllib = None

def minimal_parse(path):
    """Tiny TOML reader for our config shape. Not a general parser."""
    data = {}
    current_section = data
    section_stack = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            # Section header like [foo] or [[foo]] or [foo.bar]
            if line.startswith('['):
                inner = line.strip('[]')
                is_array = line.startswith('[[')
                parts = inner.split('.')
                node = data
                for p in parts[:-1]:
                    node = node.setdefault(p, {})
                key = parts[-1]
                if is_array:
                    node.setdefault(key, []).append({})
                    current_section = node[key][-1]
                else:
                    node[key] = {}
                    current_section = node[key]
                continue
            # key = value
            if '=' in line:
                k, v = line.split('=', 1)
                k = k.strip()
                v = v.strip()
                # Array literal: [..., ...]
                if v.startswith('['):
                    items = re.findall(r'"([^"]*)"', v)
                    current_section[k] = items
                # Quoted string
                elif v.startswith('"'):
                    current_section[k] = v.strip('"')
                # Integer
                else:
                    try:
                        current_section[k] = int(v)
                    except ValueError:
                        current_section[k] = v
    return data

def load(path):
    if tomllib:
        with open(path, 'rb') as f:
            return tomllib.load(f)
    return minimal_parse(path)

def shell_escape(value):
    """Quote a value for safe shell assignment."""
    return "'" + str(value).replace("'", "'\\''") + "'"

cfg = load(sys.argv[1])

block = cfg['fork']['block']
admin = cfg['admin_contracts'][0]
owner_check = cfg['properties']['admin_owner_in_approved_set']
origin_check = cfg['properties']['tx_origin_in_authorization']
approved = ','.join(owner_check['approved_owners'])

print(f"UG_FORK_BLOCK={shell_escape(block)}")
print(f"UG_ADMIN_ADDRESS={shell_escape(admin['address'])}")
print(f"UG_OWNER_SLOT={shell_escape(admin['owner_slot'])}")
print(f"UG_APPROVED_OWNERS_CSV={shell_escape(approved)}")
print(f"UG_OWNER_CHECK_ENABLED={shell_escape('true' if owner_check.get('enabled', True) else 'false')}")
print(f"UG_ORIGIN_CHECK_ENABLED={shell_escape('true' if origin_check.get('enabled', True) else 'false')}")

# Dependency / oracle config (optional)
deps = cfg.get('dependencies', [])
oracle_check = cfg['properties'].get('oracle_decimal_consistency', {})
oracle_enabled = oracle_check.get('enabled', False) and len(deps) > 0

if oracle_enabled:
    dep = deps[0]
    print(f"UG_ORACLE_ADDRESS={shell_escape(dep['address'])}")
    print(f"UG_ORACLE_CONSUMER={shell_escape(dep['consumers'][0])}")
    print(f"UG_ORACLE_EXPECTED_DECIMALS={shell_escape(dep['expected_decimals'])}")
    print(f"UG_ORACLE_CHECK_ENABLED={shell_escape('true')}")
else:
    print(f"UG_ORACLE_ADDRESS={shell_escape('0x0000000000000000000000000000000000000000')}")
    print(f"UG_ORACLE_CONSUMER={shell_escape('0x0000000000000000000000000000000000000000')}")
    print(f"UG_ORACLE_EXPECTED_DECIMALS={shell_escape('0')}")
    print(f"UG_ORACLE_CHECK_ENABLED={shell_escape('false')}")

# Storage layout compatibility
storage_check = cfg['properties'].get('storage_layout_compatibility', {})
storage_enabled = storage_check.get('enabled', False)
print(f"UG_STORAGE_CHECK_ENABLED={shell_escape('true' if storage_enabled else 'false')}")
print(f"UG_STORAGE_INITIALIZED_SLOT={shell_escape(storage_check.get('initialized_slot', 0))}")
approved_impls = storage_check.get('approved_impls', [])
print(f"UG_STORAGE_APPROVED_IMPLS_CSV={shell_escape(','.join(approved_impls) if approved_impls else '')}")

# Dead selector enumerator
dead_check = cfg['properties'].get('dead_selector_enumerator', {})
dead_enabled = dead_check.get('enabled', False)
print(f"UG_DEAD_CHECK_ENABLED={shell_escape('true' if dead_enabled else 'false')}")
dead_sels = dead_check.get('should_be_dead', [])
print(f"UG_DEAD_SELECTORS_CSV={shell_escape(','.join(dead_sels))}")

# Liquidity decay invariant
liq_check = cfg['properties'].get('liquidity_decay_invariant', {})
liq_enabled = liq_check.get('enabled', False)
print(f"UG_LIQ_CHECK_ENABLED={shell_escape('true' if liq_enabled else 'false')}")
print(f"UG_LIQ_LEGACY_ASSET={shell_escape(liq_check.get('legacy_asset', '0x0000000000000000000000000000000000000000'))}")
print(f"UG_LIQ_ORACLE_SOURCE={shell_escape(liq_check.get('oracle_source', '0x0000000000000000000000000000000000000000'))}")
print(f"UG_LIQ_SAFETY_RATIO={shell_escape(liq_check.get('safety_ratio', 30000))}")
