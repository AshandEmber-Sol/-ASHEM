# Ash & Ember ($ASHEM)

Memecoin en Solana sobre el programa Token-2022 (spl-token-2022), usando solo extensiones nativas: sin Anchor, sin contratos custom.

Supply inicial 1,000,000,000 | Decimales 9 | Extension TransferFeeConfig (1.5% con tope por transaccion) | Piso de circulante 300,000,000.

Transparencia: la extension Transfer Fee NO quema tokens por si sola; solo retiene un porcentaje en cada transferencia. La quema real es un paso explicito de burn ejecutado por un script (harvest de fees, burn, y apagado automatico del fee al llegar al piso de 300M).

Trabajo en progreso. La documentacion completa de comandos, scripts y la GitHub Action se ira agregando en este repositorio.

## Endgame automatizado (scripts/endgame.sh)

Un solo script publico ejecuta todo el ciclo de vida del mecanismo de quema,
incluida su propia terminacion. Corre por cron (GitHub Actions). Cada run lee
el estado REAL on-chain, deriva un estado y ejecuta como maximo UNA accion:

IDLE -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_BURN -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE

- Disparo con buffer dinamico: fee->0 se programa en supply <= 300M + (burn diario promedio 7d x 5 dias), porque el switchover de epoca (~2-4.5 dias en mainnet) deja la quema corriendo. Fallback documentado: DEFAULT_DAILY_BURN en el script mientras no haya historial.
- Idempotente: el estado NUNCA se persiste localmente; cada run lo deriva del mint. Un run interrumpido en cualquier punto retoma sin duplicar burns ni saltarse revocaciones (probado: T4).
- La revocacion de ambas llaves ya esta escrita en el codigo: pasos REVOKE_WITHDRAW y REVOKE_FEE_CONFIG de scripts/endgame.sh.

### Resultados de pruebas en validador local (epocas de 32 slots)

- T1: un cambio de fee programado SI se ejecuta aunque la transfer-fee-config authority se revoque durante el switchover. La revocacion solo bloquea cambios nuevos.
- T2: harvest + burn reduce el supply exactamente por el monto retenido.
- T3: secuencia E2E completa hasta DONE con ambas authorities en None.
- T4: interrupcion a mitad de FINAL_HARVEST_BURN -> el siguiente run recupera desde el estado on-chain (incluye la rama vault-con-saldo-sin-withheld).
- T5: con burn rate simulado de 8M/dia el disparo ocurrio en 300M+40M y el supply final quedo >= 300M.

### Custodia de la llave (decision)

GitHub Actions secret (opcion a). Razones: el workflow es auditable linea por linea (coherente con "legibilidad como feature"); el radio de dano de la llave es acotado y publico (no mintea, no congela, no toca LP; peor caso = desviar fees retenidos o programar un cambio de fee visible on-chain ~2 epocas antes de aplicar); y la llave tiene fecha de muerte programada en REVOKE_WITHDRAW/REVOKE_FEE_CONFIG. Un entorno de firma separado (opcion b) protege mas la llave pero rompe la legibilidad para auditores externos, que es el activo del proyecto.

### Automatizacion (GitHub Actions)

`.github/workflows/endgame.yml` ejecuta `scripts/endgame.sh` cada 6 horas (y a demanda con workflow_dispatch):

- Configuracion requerida en Settings del repo:
  - Variables publicas: `ASHEM_MINT`, `ASHEM_VAULT`, `ASHEM_RPC_URL`
  - Secret: `ASHEM_AUTHORITY_KEYPAIR` (JSON del keypair de la authority; ver "Custodia de la llave")
- Mientras las variables no existan, el workflow se salta la ejecucion con exit limpio (se puede commitear antes de configurar la red).
- Cada run committea `state/` (historial de supply + log de decisiones y firmas) de vuelta al repo: la auditoria completa vive en el historial de git.
- CLI de Solana pineada a la version probada en los tests locales (v4.0.2).

### Fee split (1.0% quema / 0.5% dev)

El transfer fee sigue siendo **1.5% total** para quien transfiere (el cap de 100,000 $ASHEM no cambia). Al hacer harvest, los fees recolectados se DIVIDEN:

- **2/3 -> quema** (baja el supply hacia el piso de 300M)
- **1/3 -> wallet de dev** (sostenimiento del proyecto, flujo transparente on-chain)

Regla de redondeo (citable): `dev_cut = floor(total/3)`, el residuo va a `burn_cut`. **El redondeo SIEMPRE favorece la quema, nunca al dev.**

La wallet de dev es un **destino, no una autoridad**: no firma nada, no tiene poder sobre el mint, solo recibe. No se introdujo ninguna llave nueva por el split (usa la withdraw-withheld authority existente). El transfer al dev paga el 1.5% como cualquier holder (Token-2022 no exime cuentas); el burn es fee-free, por lo que el supply baja exactamente por `burn_cut`. Cuando llega el endgame (fee 0% + llaves revocadas), el flujo al dev muere junto con la quema.

El log de cada harvest queda en `state/harvest-ledger.csv` (`ts,total,burn_cut,dev_cut,burn_sig,dev_sig`), para que cualquiera pueda sumar cuánto se ha quemado vs. cuánto ha ido al dev, sin confiar en nadie.

Estados de la maquina: `IDLE -> HARVEST_SPLIT -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_SPLIT -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE`.

**Requisito de RPC:** el paso de harvest usa `getProgramAccounts` para enumerar las cuentas con fees retenidos. Los RPC publicos (devnet y mainnet) bloquean esa consulta sobre el programa Token-2022, asi que se requiere un RPC indexador (p. ej. Helius) en la variable `ASHEM_INDEXER_RPC` (secret). El resto de operaciones usan el RPC normal (`ASHEM_RPC_URL`).

Config requerida adicional en Settings del repo: variable publica `ASHEM_DEV_WALLET` y secret `ASHEM_INDEXER_RPC`.

**CRITICO — la wallet de vault:** `ASHEM_VAULT` debe ser una cuenta de token DEDICADA y vacia al inicio, usada SOLO para recolectar fees. NUNCA debe ser la tesoreria ni ninguna cuenta con saldo real: el harvest+split parte todo el saldo del vault. Como salvaguarda, el script aborta sin mover nada si un solo harvest moveria mas del 10% del supply (probable misconfiguracion).
