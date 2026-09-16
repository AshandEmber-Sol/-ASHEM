# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-16T21:25:39Z

**Semáforo:** 🟡
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/35152278253
**Harvest:** OK — total=3750000 burn=2500000 dev=1250000 (2/3:1/3, residuo→quema); ledger +1 fila (sin duplicados)
**Circuit breaker:** OK — el mayor harvest del ciclo fue 0.0000% del supply (cap 10%)
**Buffer dinámico:** 639526648 vs 304177414 (300M + buffer 4177414) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (sin cambio de estado)
**Idempotencia:** recuperación detectada — HARVEST_SPLIT resume inflight total=3750000 dev_cut=1250000
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=2500000 mint_withheld=0; acumulado quemado=10473350219730944 dev=5236675109865457 (base units). Notas 🟡: run retomó un split en vuelo (resume inflight); verificar que no duplicó ni saltó.
