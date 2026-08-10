# $ASHEM — Endgame health log

Generado automáticamente por `scripts/health-report.sh` al final de cada
run del workflow `endgame.yml`. **Solo lectura**: reporta salud técnica del
mecanismo sin ejecutar ninguna acción correctiva. Cada entrada es un APPEND;
el historial nunca se sobrescribe. Este archivo es el puente para monitoreo
off-repo (Cowork): se lee sin tocar el log crudo, el Codespace ni ningún secret.

---

## Endgame health — 2026-08-10T19:23:23Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/31423801226
**Harvest:** OK — sin withheld que recolectar este ciclo (IDLE)
**Circuit breaker:** OK — sin harvest este ciclo, nada que evaluar contra el cap
**Buffer dinámico:** 1000000000 vs 307500000 (300M + buffer 7500000) — disparado: no
**Máquina de estados:** IDLE (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=n/a dev=n/a (base units).

---
