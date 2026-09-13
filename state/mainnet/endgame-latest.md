# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-13T04:58:12Z

**Semáforo:** 🟡
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/34739120966
**Harvest:** OK — total=34394919 burn=22929946 dev=11464973 (2/3:1/3, residuo→quema); ledger +1 fila (sin duplicados)
**Circuit breaker:** OK — el mayor harvest del ciclo fue 0.0000% del supply (cap 10%)
**Buffer dinámico:** 639546749 vs 567226929 (300M + buffer 267226929) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (sin cambio de estado)
**Idempotencia:** recuperación detectada — HARVEST_SPLIT resume inflight total=34394919 dev_cut=11464973
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=22929946 mint_withheld=0; acumulado quemado=10453249717115714 dev=5226624858557845 (base units). Notas 🟡: run retomó un split en vuelo (resume inflight); verificar que no duplicó ni saltó.
