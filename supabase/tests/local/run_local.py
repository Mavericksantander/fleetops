#!/usr/bin/env python3
"""Aplica shim + migraciones + tests sobre un Postgres local vacío.
Uso: python run_local.py "host=/tmp port=54329 user=postgres dbname=fleetops_t012"
Requiere psycopg 3. SKIP_HARDENING=1 aplica solo el baseline (control negativo: los tests deben FALLAR). No se conecta a Supabase."""
import os, sys, pathlib, psycopg
root = pathlib.Path(__file__).resolve().parents[2]
files = [root/'tests/local/00_supabase_shim.sql',
         *[m for m in sorted((root/'migrations').glob('*.sql')) if not (os.environ.get('SKIP_HARDENING') and 't012' in m.name)],
         root/'tests/t012_rls_isolation_test.sql']
with psycopg.connect(sys.argv[1], autocommit=True) as c:
    c.add_notice_handler(lambda d: print('  NOTICE:', d.message_primary))
    for f in files:
        print('==>', f.relative_to(root))
        c.execute(f.read_text())
print('OK: todo aplicado y todas las aserciones pasaron')
