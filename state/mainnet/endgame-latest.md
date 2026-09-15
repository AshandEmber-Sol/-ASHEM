# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-15T21:29:52Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/35025906759
**Harvest:** OK — total=30000000000000 burn=20000000000000 dev=10000000000000 (2/3:1/3, residuo→quema); ledger +1 fila (sin duplicados)
**Circuit breaker:** OK — el mayor harvest del ciclo fue 0.0047% del supply (cap 10%)
**Buffer dinámico:** 639546749 vs 304160374 (300M + buffer 4160374) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (transición IDLE→HARVEST_SPLIT, ok)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~2 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=10473249717230944 dev=5236624858615457 (base units).
