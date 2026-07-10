# $ASHEM — Estado tecnico del proyecto

**Ultima actualizacion:** 2026-07-09
**Repo:** AshandEmber-Sol/-ASHEM

## 1. Resumen

La mecanica completa del token (creacion, quema automatizada, apagado con buffer, endgame con revocacion de llaves y automatizacion por cron) esta construida, probada en validador local (T1-T5) y ensayada end-to-end contra devnet real en GitHub Actions. Cero bloqueadores tecnicos. Pendiente unico: despliegue a mainnet (decision de negocio + distribucion/LP).

Principio de diseno respetado: cero programas on-chain custom, cero Anchor. Todo se apoya en extensiones nativas de Token-2022 + scripts off-chain legibles.

## 2. Parametros del token

| Parametro | Valor |
|---|---|
| Programa | Token-2022 (TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb) |
| Supply inicial | 1,000,000,000 |
| Decimales | 9 |
| Transfer fee | 150 bps (1.5%) |
| Fee maximo por tx | 100,000 $ASHEM |
| Piso de circulante | 300,000,000 (30%) |
| Mint authority | Revocada (supply fijo) |
| Freeze authority | Revocada |

## 3. Estado on-chain en DEVNET (verificado)

> Direcciones de devnet (efimeras, sin valor). En mainnet se recrea todo con wallet nueva y cambian.

| Elemento | Direccion |
|---|---|
| Mint | H6cpRwEW8AxQwfWnP4iun2jWgCP2Smdn2zprMFtHuvUu |
| Tesoreria (ATA) | 8Z1YyMmHHUMmtGCutNFhwqvSgGCWfy7tXsRBeuaYPeZz |
| Wallet de autoridades (devnet) | DFPuDWketoZJqeuHkWL2Ev7JM76ism1FXTjWnK4VVhaV |

Estado leido on-chain: supply 1B, fee 150bps, cap 100k, mint/freeze authority not set, config + withdraw authority en la wallet dedicada, withheld 0.

## 4. Arquitectura de la quema (version honesta)

El transfer fee de Token-2022 NO quema ni reduce supply por si solo: solo retiene un % en cada transferencia. La quema real es un paso explicito scripteado:

    transfer fee retiene 1.5% -> harvest de fees retenidos -> burn (esto SI baja el supply)
    -> al llegar al piso: apagar el fee -> quema final -> revocar ambas llaves -> publicar prueba

Todo vive en scripts/endgame.sh, una maquina de estados que en cada corrida lee el estado real on-chain (nunca confia en estado local), deduce en que punto esta y ejecuta UNA sola accion:

    IDLE -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_BURN
    -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE

Los nombres de estado aparecen literales en el codigo y en los logs.

## 5. Resultados de pruebas (validador local, epocas aceleradas)

| Test | Que valida | Resultado |
|---|---|---|
| T1 | El switchover programado (fee->0) se ejecuta aunque se revoque la config authority durante la ventana | OK (2 veces) |
| T2 | Harvest + burn reduce el supply exactamente por el monto quemado | OK |
| T3 | Secuencia E2E completa hasta DONE, ambas authorities en None | OK |
| T4 | Interrupcion a mitad de la quema -> recuperacion sin duplicar ni saltar pasos | OK |
| T5 | Buffer dinamico dispara en piso+buffer y el supply final queda >= 300M | OK (final 303,899,995) |

## 6. Ensayo en DEVNET real (run #9, GitHub Actions, exito)

El workflow corrio el ciclo completo contra el mint real de devnet. Log:

    STATE=IDLE supply=1000000000 floor=300000000 buffer=7500000
    trigger=307500000 cur_fee=150bps mint_withheld=0

Leyo correctamente el estado on-chain real y decidio IDLE (correcto, supply >> piso). El secret desencripto y firmo bien; el paso de commit escribio state/ de vuelta al repo. El buffer 7.5M es el fallback conservador (DEFAULT_DAILY_BURN 1.5M/dia x 5) mientras no exista historial.

## 7. Automatizacion y custodia

- Workflow: .github/workflows/endgame.yml, cron cada 6h (0 */6 * * *) + disparo manual. CLI de Solana pineada a v4.0.2. Salta limpio si faltan variables.
- Custodia: opcion (a), GitHub Actions secret. La llave existe solo durante cada corrida. Radio de dano acotado y publico: NO mintea, NO congela, NO toca LP; peor caso = desviar fees retenidos o programar un cambio de fee visible on-chain ~2 epocas (2-4.5 dias) antes de aplicar. Tiene fecha de muerte programada en el script.
- Auditabilidad: cada corrida commitea state/ (historial de supply + log de decisiones y firmas). La historia completa vive en git.

## 8. Datos para el thread

1. T1 confirmado: el apagado del fee, una vez programado, lo ejecuta el protocolo aunque quememos la llave.
2. Custodia: opcion (a), documentada en el README.
3. Buffer dinamico implementado: sostiene "hard floor at 300M".
4. Revocacion ya escrita: scripts/endgame.sh, lineas 114 (withdraw-withheld) y 118 (transfer-fee-config).

## 9. Matices de honestidad (declararlos primero)

- Son DOS autoridades activas, no "una": fee-config authority y withdraw-withheld authority, ambas en la wallet dedicada.
- La quema es promesa verificable, no garantia de protocolo: la withdraw authority tecnicamente podria desviar fees. Defensa: cada harvest/withdraw/burn es publico y el supply es auditable.
- WAIT_SWITCHOVER con epocas reales: probado en local (T1), pero su primera ejecucion en vivo (epocas ~2 dias) sera cuando el supply real llegue al trigger en mainnet.

## 10. Pendiente (decisiones de estrategia, no ingenieria)

1. Despliegue a mainnet: wallet nueva dedicada + SOL real (~0.02) + recrear mint con comandos ya validados + actualizar variables del repo + cargar el secret de la llave nueva con maximo cuidado.
2. Distribucion / liquidez (LP).
3. Timing del lanzamiento y publicacion del thread.

Bloqueadores tecnicos: ninguno.
