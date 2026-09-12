# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-12T03:55:07Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/34671621226
**Harvest:** OK — sin withheld que recolectar este ciclo (IDLE)
**Circuit breaker:** OK — sin harvest este ciclo, nada que evaluar contra el cap
**Buffer dinámico:** 999778318 vs 307500000 (300M + buffer 7500000) — disparado: no
**Máquina de estados:** IDLE (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=221681748743709 dev=110840874371837 (base units).
