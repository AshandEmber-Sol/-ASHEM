# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-17T05:00:43Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/35184033090
**Harvest:** OK — total=18750 burn=12500 dev=6250 (2/3:1/3, residuo→quema); ledger +1 fila (sin duplicados)
**Circuit breaker:** OK — el mayor harvest del ciclo fue 0.0000% del supply (cap 10%)
**Buffer dinámico:** 639526648 vs 300171955 (300M + buffer 171955) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~2 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=10473350219743444 dev=5236675109871707 (base units).
