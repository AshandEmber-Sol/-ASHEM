# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-12T04:44:18Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/34673768965
**Harvest:** OK — total=275159346568665 burn=183439564379110 dev=91719782189555 (2/3:1/3, residuo→quema); ledger +1 fila (sin duplicados)
**Circuit breaker:** OK — el mayor harvest del ciclo fue 0.0430% del supply (cap 10%)
**Buffer dinámico:** 639731110 vs 566875454 (300M + buffer 266875454) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~2 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=10452327910374762 dev=5226163955187369 (base units).
