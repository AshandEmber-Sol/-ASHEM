# $ASHEM — Fee Split (1.0% quema / 0.5% dev): implementado y verificado

**De:** sesion de Claude Code · **Fecha:** 2026-07-10 · **Commit:** 0286492 en main
**Depende de:** infraestructura previa (harvest + maquina de estados). Fue una modificacion al harvest + un gap corregido, no un rediseno.

## Las 4 confirmaciones

### 1. Split implementado y verificado en devnet
Se puede publicar "1% burned, 0.5% sustains development" con prueba. De cada harvest: `dev_cut = floor(total/3)` va al dev, el resto se quema. El supply baja EXACTAMENTE por lo quemado (el burn es fee-free). Verificado on-chain:

- **S1 (split divisible):** withheld 45,000 -> 30,000 quemados / 15,000 al dev · supply -30,000 exacto · conservacion exacta.
- **S2 (redondeo):** withheld no divisible por 3 -> el residuo va A LA QUEMA, nunca al dev. Regla citable: "rounding always favors the burn."
- **S3 (endgame):** el split final ocurre ANTES de revocar las llaves; tras revocar, cero flujo al dev.
- **S4 (interrupcion):** matando el proceso entre el pago al dev y la quema, el re-run completa solo lo que falta, sin duplicar el pago.

### 2. Wallet de dev: SEPARADA de la de autoridades
Direccion publica: `Bn1g4i66pnYHzftdhkpnzTYunBhBZmFvjCyLJZpuf3bN`
Es unicamente un destino de transferencia: no firma nada, no tiene autoridad sobre el mint, solo recibe. Lectura limpia para el auditor: "esta recibe el 0.5%, la otra tiene las llaves."

### 3. Nombre final del estado
`FINAL_HARVEST_BURN` -> renombrado a **`FINAL_HARVEST_SPLIT`**. Citarlo asi literal (aparece igual en codigo y logs).

### 4. Ninguna llave nueva por el split
Usa la withdraw-withheld authority EXISTENTE. Sigue siendo el mismo esquema de dos llaves. La revocacion ya esta escrita en el codigo:
`scripts/endgame.sh`, **linea 162** (`withheld-withdraw --disable`) y **linea 166** (`transfer-fee-config --disable`).
NOTA: estas lineas cambiaron respecto a las 114/118 del entregable anterior — actualizar cualquier cita.

## Dos cosas a declarar primero (antes que un auditor)

- **El 0.5% del dev tambien paga el 1.5% de fee**, como cualquier holder — Token-2022 no exime cuentas. El vault debita exactamente `dev_cut`; la cuenta del dev lo recibe con su 1.5% retenido dentro. Narrativa a favor: "el dev no tiene trato especial: su cut paga el mismo fee que todos."
- **El mecanismo de quema hacia 300M no existia en el codigo anterior** (solo quemaba en el endgame -> el supply nunca bajaba -> el trigger nunca se cumplia). Se corrigio agregando el harvest+split continuo (cada 6h). Ahora la quema hacia el piso es real.

## Hallazgo de infraestructura (impacta el setup de mainnet)

El harvest necesita `getProgramAccounts` para enumerar las cuentas con fees retenidos, y los RPC publicos (devnet y mainnet) BLOQUEAN esa consulta sobre Token-2022. Se requiere un RPC indexador (tipo Helius) como secret (`ASHEM_INDEXER_RPC`). Es una dependencia y un costo nuevos para mainnet.

## Salvaguarda: circuit breaker (imposible drenar el token por error)

El harvest+split continuo parte el saldo del vault. Para blindar contra una config erronea (vault apuntando a la tesoreria) o alguien enviando tokens al vault, el script tiene un fusible: aborta sin mover NI UN token si un solo harvest moveria mas del 10% del supply. Los fees reales por ciclo son minusculos; cualquier monto anormal = probable error, y el script no hace nada.

Esto se detecto y corrigio probando en devnet: la primera corrida del workflow tenia el vault mal configurado (apuntaba a la tesoreria con 1B) y el split partio todo el saldo. Solo devnet, sin valor. El fusible ya cubre ese caso: verificado que con la misma config catastrofica, aborta y deja supply y tesoreria intactos.

Frase citable: "el mecanismo no puede mover mas del 10% del supply por ciclo - es imposible drenar el token por un error de configuracion."

## Auditabilidad

Cada harvest queda en `state/harvest-ledger.csv` (`ts, total, burn_cut, dev_cut, burn_sig, dev_sig`), commiteado por el bot del workflow. Cualquiera puede sumar cuanto se ha quemado vs. cuanto ha ido al dev, sin confiar en el repo.

**Estado:** commiteado y probado en devnet. Sin bloqueadores tecnicos para el patch de contenido "quema total -> split".
