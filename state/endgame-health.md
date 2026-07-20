# $ASHEM — Endgame health log

Generado automáticamente por `scripts/health-report.sh` al final de cada
run del workflow `endgame.yml`. **Solo lectura**: reporta salud técnica del
mecanismo sin ejecutar ninguna acción correctiva. Cada entrada es un APPEND;
el historial nunca se sobrescribe. Este archivo es el puente para monitoreo
off-repo (Cowork): se lee sin tocar el log crudo, el Codespace ni ningún secret.

---

## Endgame health — 2026-07-20T21:52:01Z

**Semáforo:** 🟢
**Run revisado:** entrada semilla generada localmente del estado actual; las proximas las genera el workflow
**Harvest:** OK — sin withheld que recolectar este ciclo (IDLE)
**Circuit breaker:** OK — sin harvest este ciclo, nada que evaluar contra el cap
**Buffer dinámico:** 999778388 vs 300000223 (300M + buffer 223) — disparado: no
**Máquina de estados:** IDLE (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=221611396984910 dev=110805698492441 (base units).

---

## Endgame health — 2026-07-20T23:02:20Z

**Semáforo:** 🟢
**Run revisado:** https://github.com/AshandEmber-Sol/-ASHEM/actions/runs/29785892234
**Harvest:** OK — sin withheld que recolectar este ciclo (IDLE)
**Circuit breaker:** OK — sin harvest este ciclo, nada que evaluar contra el cap
**Buffer dinámico:** 999778388 vs 300000221 (300M + buffer 221) — disparado: no
**Máquina de estados:** IDLE (sin cambio de estado)
**Idempotencia:** OK — sin split en vuelo, vault drenado a 0
**Indexador:** ~1 llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)
**Anomalía vs. falla de harvest conocida:** N/A
**Detalle libre:** cur_fee=150bps up_fee=n/abps vault_raw=0 mint_withheld=0; acumulado quemado=221611396984910 dev=110805698492441 (base units).

---
