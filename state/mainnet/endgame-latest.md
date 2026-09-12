# $ASHEM — Endgame health (latest run only)

Auto-generado por `scripts/health-report.sh`: SOLO la última entrada, se
sobrescribe cada run. Puente para monitoreo off-repo (Cowork) a prueba de
truncamiento por tamaño; el historial completo append-only vive en
`endgame-health.md`.

---

## Endgame health — 2026-09-12T20:39:57Z

**Semáforo:** 🔴
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/34717731237
**Harvest:** FALLO — hubo withdraw pero no se completó el split (murió a mitad)
**Circuit breaker:** OK — sin harvest este ciclo, nada que evaluar contra el cap
**Buffer dinámico:** 639546749 vs 570622305 (300M + buffer 270622305) — disparado: no
**Máquina de estados:** HARVEST_SPLIT (sin cambio de estado)
**Idempotencia:** split-inflight presente al terminar — plan de split sin cerrar
**Indexador:** ~2 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** fallo no-atrapado durante la operación (post-lectura): unexpected failure (exit 1) at line 130: burn_sig="$(spl-token burn "$VAULT" ALL | sig_of)"
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=10453249694185768 dev=5226624847092872 (base units). HALLAZGOS 🔴: withdraw sin 'ok total=' subsiguiente: split incompleto este run;el trap ERR disparó después de iniciar el ciclo (STATE=HARVEST_SPLIT): unexpected failure (exit 1) at line 130: burn_sig="$(spl-token burn "$VAULT" ALL | sig_of)";endgame step outcome=failure. Notas 🟡: state/split-inflight sigue presente tras el run; próximo ciclo debe retomarlo.
