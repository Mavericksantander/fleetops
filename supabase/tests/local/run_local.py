#!/usr/bin/env python3
"""Aplica shim + migraciones + tests sobre un Postgres local vacío.
Uso: python run_local.py "dbname=fleetops_t012"
Requiere psycopg 3. SKIP_HARDENING=1 aplica solo el baseline (control negativo de T-012: los tests deben FALLAR) y no corre el test de Storage. No se conecta a Supabase."""
import os, sys, pathlib, psycopg
root = pathlib.Path(__file__).resolve().parents[2]
skip = bool(os.environ.get('SKIP_HARDENING'))
migrations = sorted((root/'migrations').glob('*.sql'))
if skip:
    migrations = [m for m in migrations if 'baseline' in m.name]
files = [root/'tests/local/00_supabase_shim.sql', *migrations, root/'tests/t012_rls_isolation_test.sql']
if not skip:
    files.append(root/'tests/storage_org_isolation_test.sql')
    files.append(root/'tests/anon_storage_policies_test.sql')
    files.append(root/'tests/onboarding_invite_binding_test.sql')
with psycopg.connect(sys.argv[1], autocommit=True) as c:
    c.add_notice_handler(lambda d: print('  NOTICE:', d.message_primary))
    for f in files:
        print('==>', f.relative_to(root))
        c.execute(f.read_text())
print('OK: todo aplicado y todas las aserciones pasaron')
