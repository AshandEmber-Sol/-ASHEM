#!/usr/bin/env bash
# =============================================================================
# $ASHEM endgame HEALTH REPORT - read-only bridge to off-repo monitoring.
#
# Runs as the LAST step of the endgame workflow, AFTER endgame.sh. It reads
# ONLY the files endgame.sh already produced this run (state/endgame-log.txt,
# state/harvest-ledger.csv, state/supply-history.csv) plus the workflow's exit
# outcome, and APPENDS one entry to state/endgame-health.md.
#
# HARD RULES (separation of responsibilities):
#   * It NEVER calls solana/spl-token or any RPC. Every on-chain fact it needs
#     was already written by endgame.sh into the run's "STATE=" log line, so it
#     duplicates zero RPC calls (satisfies the indexer free-tier budget, §5).
#   * It NEVER takes a corrective action: no retry, no fee change, no authority
#     touch. On a 🔴 its ONLY job is to write the finding down clearly; the
#     decision to intervene stays with a human in-session.
#   * It NEVER rewrites history: it always APPENDS, never overwrites past entries.
#
# Inputs (env, set by the workflow):
#   RUN_URL          link to the current GitHub Actions run
#   ENDGAME_OUTCOME  outcome of the endgame step ('success' | 'failure' | ...)
#   PREV_LOGLINES    line count of endgame-log.txt captured BEFORE endgame.sh ran
#                    (so we slice exactly the lines THIS run appended)
# =============================================================================
set -uo pipefail   # NOTE: no -e; a reporter must finish and write its finding
                   # even when something it inspects looks wrong.

STATE_DIR="state"
LOGF="$STATE_DIR/endgame-log.txt"
LEDGER="$STATE_DIR/harvest-ledger.csv"
HEALTH="$STATE_DIR/endgame-health.md"
UNIT=1000000000            # 10^decimals, same as endgame.sh
FLOOR=300000000

RUN_URL="${RUN_URL:-(local run - no GitHub Actions URL)}"
ENDGAME_OUTCOME="${ENDGAME_OUTCOME:-success}"
PREV_LOGLINES="${PREV_LOGLINES:-}"

# ---- slice of the log this run appended --------------------------------------
# If PREV_LOGLINES is known we take exactly the new tail; otherwise we fall back
# to "from the last STATE= line to EOF" (endgame.sh logs exactly one per run).
RUN_LOG=""
if [[ -f "$LOGF" ]]; then
  total_lines="$(wc -l < "$LOGF" | tr -d ' ')"
  if [[ -n "$PREV_LOGLINES" ]] && (( total_lines >= PREV_LOGLINES )); then
    new_lines=$(( total_lines - PREV_LOGLINES ))
    (( new_lines > 0 )) && RUN_LOG="$(tail -n "$new_lines" "$LOGF")"
  else
    last_state_ln="$(grep -n ' STATE=' "$LOGF" | tail -1 | cut -d: -f1)"
    [[ -n "$last_state_ln" ]] && RUN_LOG="$(tail -n +"$last_state_ln" "$LOGF")"
  fi
fi

STATE_LINE="$(grep ' STATE=' <<<"$RUN_LOG" | tail -1)"
kv() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" <<<"$STATE_LINE" | head -1; }

STATE="$(kv STATE)"
SUPPLY="$(kv supply)"
BUFFER="$(kv buffer)"
TRIGGER="$(kv trigger)"
CUR_FEE="$(kv cur_fee)"
UP_FEE="$(kv up_fee)"
VAULT_RAW="$(kv vault_raw)"
MINT_WITHHELD="$(kv mint_withheld)"
TS="$(sed -n 's/^\([0-9T:-]*Z\) .*/\1/p' <<<"$STATE_LINE" | head -1)"
[[ -z "$TS" ]] && TS="$(date -u +%FT%TZ)"

# ---- accumulators ------------------------------------------------------------
REDS=(); YELLOWS=()
red()    { REDS+=("$1"); }
yellow() { YELLOWS+=("$1"); }

# ============================================================================
# 1) HARVEST
# ============================================================================
HARVEST_FIELD=""
ok_line="$(grep -E 'HARVEST_SPLIT ok total=' <<<"$RUN_LOG" | tail -1)"
abort_line="$(grep -E 'ABORT:' <<<"$RUN_LOG" | tail -1)"
error_line="$(grep -E 'ERROR:' <<<"$RUN_LOG" | tail -1)"
resume_line="$(grep -E 'resume inflight' <<<"$RUN_LOG" | tail -1)"

if [[ -n "$abort_line" ]]; then
  HARVEST_FIELD="FALLO — circuit breaker abortó el ciclo: ${abort_line#*ABORT: }"
  red "circuit breaker ABORT (endgame.sh línea 87): ${abort_line#*ABORT: }"
elif [[ -n "$error_line" ]]; then
  HARVEST_FIELD="FALLO — ${error_line#*ERROR: }"
  red "ERROR reportado por endgame.sh: ${error_line#*ERROR: }"
elif [[ -n "$ok_line" ]]; then
  h_total="$(sed -n 's/.* total=\([0-9]*\).*/\1/p' <<<"$ok_line")"
  h_burn="$(sed -n 's/.* burn=\([0-9]*\).*/\1/p' <<<"$ok_line")"
  h_dev="$(sed -n 's/.* dev=\([0-9]*\).*/\1/p' <<<"$ok_line")"
  h_burnsig="$(sed -n 's/.* burn_sig=\([^ ]*\).*/\1/p' <<<"$ok_line")"
  # Invariant: burn + dev == total, and the rounding remainder went to the burn.
  if [[ -n "$h_total" && -n "$h_burn" && -n "$h_dev" ]] && (( h_burn + h_dev == h_total )); then
    exp_dev=$(( h_total / 3 ))               # dev_cut = floor(total/3)
    if (( h_dev == exp_dev )) && (( h_burn == h_total - exp_dev )); then
      HARVEST_FIELD="OK — total=$h_total burn=$h_burn dev=$h_dev (2/3:1/3, residuo→quema)"
    else
      HARVEST_FIELD="OK — total=$h_total burn=$h_burn dev=$h_dev (suma cuadra; split≠2/3:1/3 esperado)"
      yellow "split $h_burn/$h_dev no coincide con floor(total/3)=$exp_dev (suma sí cuadra)"
    fi
    # Ledger cross-check: last row must match this harvest, and appear once.
    if [[ -f "$LEDGER" ]]; then
      last_row="$(tail -1 "$LEDGER")"
      l_total="$(cut -d, -f2 <<<"$last_row")"; l_burn="$(cut -d, -f3 <<<"$last_row")"; l_dev="$(cut -d, -f4 <<<"$last_row")"
      # Dupe test keyed on the burn SIGNATURE (globally unique), NOT the amounts:
      # tiny harvests legitimately repeat (1,1,0), so amount-matching false-positives.
      dupes=0
      [[ -n "$h_burnsig" && "$h_burnsig" != "already" ]] && dupes="$(grep -c "$h_burnsig" "$LEDGER" 2>/dev/null)"
      if [[ "$l_total" != "$h_total" || "$l_burn" != "$h_burn" || "$l_dev" != "$h_dev" ]]; then
        HARVEST_FIELD="$HARVEST_FIELD; ledger NO coincide con el harvest"
        red "harvest-ledger.csv última fila ($l_total,$l_burn,$l_dev) ≠ harvest ($h_total,$h_burn,$h_dev)"
      elif [[ "${dupes:-0}" -gt 1 ]]; then
        HARVEST_FIELD="$HARVEST_FIELD; ledger con firma DUPLICADA"
        red "harvest-ledger.csv tiene $dupes filas con la misma burn_sig (idempotencia)"
      else
        HARVEST_FIELD="$HARVEST_FIELD; ledger +1 fila (sin duplicados)"
      fi
    fi
  else
    HARVEST_FIELD="FALLO — invariante burn+dev==total rota en: $ok_line"
    red "invariante del split rota (burn+dev≠total)"
  fi
elif grep -q 'harvest ok withdraw_sig=' <<<"$RUN_LOG"; then
  HARVEST_FIELD="FALLO — hubo withdraw pero no se completó el split (murió a mitad)"
  red "withdraw sin 'ok total=' subsiguiente: split incompleto este run"
elif [[ -z "$STATE" ]]; then
  HARVEST_FIELD="no verificable — el run no dejó línea de estado en el log"
elif [[ "$STATE" == "IDLE" ]]; then
  HARVEST_FIELD="OK — sin withheld que recolectar este ciclo (IDLE)"
else
  HARVEST_FIELD="OK — este estado ($STATE) no ejecuta harvest"
fi

# ============================================================================
# 2) CIRCUIT BREAKER (cap = 10% del supply por harvest; endgame.sh línea 87)
# ============================================================================
CB_FIELD=""
if [[ -n "$abort_line" ]]; then
  CB_FIELD="EXCEDIDO — el fusible abortó el ciclo sin mover tokens"
elif [[ -n "${h_total:-}" && -n "$SUPPLY" && "$SUPPLY" -gt 0 ]]; then
  # pct = h_total / (supply*UNIT) * 100, con 4 decimales vía enteros
  pct_bp="$(awk -v t="$h_total" -v s="$SUPPLY" -v u="$UNIT" 'BEGIN{printf "%.4f", (t*100.0)/(s*u)}')"
  CB_FIELD="OK — el mayor harvest del ciclo fue ${pct_bp}% del supply (cap 10%)"
  awk -v p="$pct_bp" 'BEGIN{exit !(p+0 >= 8.0)}' && { CB_FIELD="cerca del cap (${pct_bp}%)"; yellow "harvest a ${pct_bp}% del supply, acercándose al cap del 10%"; }
else
  CB_FIELD="OK — sin harvest este ciclo, nada que evaluar contra el cap"
fi

# ============================================================================
# 3) BUFFER DINÁMICO (dispara SET_FEE_ZERO cuando supply <= FLOOR+buffer)
# ============================================================================
BUF_FIELD=""
fired="no"
case "$STATE" in
  SET_FEE_ZERO|WAIT_SWITCHOVER|FINAL_HARVEST_SPLIT|REVOKE_WITHDRAW|REVOKE_FEE_CONFIG|PUBLISH_PROOF|DONE) fired="sí" ;;
esac
if [[ -n "$SUPPLY" && -n "$TRIGGER" ]]; then
  BUF_FIELD="$SUPPLY vs $TRIGGER (300M + buffer $BUFFER) — disparado: $fired"
  # Sanity: si supply<=trigger el mismo run debió disparar SET_FEE_ZERO.
  if (( SUPPLY <= TRIGGER )) && [[ "$STATE" == "IDLE" || "$STATE" == "HARVEST_SPLIT" ]]; then
    yellow "supply≤trigger pero STATE=$STATE (no disparó SET_FEE_ZERO); revisar timing/época"
  fi
else
  BUF_FIELD="no verificable — falta supply/trigger en el log de este run"
  yellow "no se pudo leer supply/trigger del run"
fi

# ============================================================================
# 4) MÁQUINA DE ESTADOS + chequeo de salto de paso
# ============================================================================
SM_FIELD="${STATE:-desconocido}"
# Transición legal según el grafo de estados de endgame.sh (cabeceras §States).
prev_state="$(grep ' STATE=' "$LOGF" 2>/dev/null | sed -n 's/.* STATE=\([A-Z_]*\).*/\1/p' | tail -2 | head -1)"
legal_next() {
  case "$1" in
    IDLE)                 [[ "$2" =~ ^(IDLE|HARVEST_SPLIT|SET_FEE_ZERO)$ ]] ;;
    HARVEST_SPLIT)        [[ "$2" =~ ^(HARVEST_SPLIT|IDLE|SET_FEE_ZERO)$ ]] ;;
    SET_FEE_ZERO)         [[ "$2" =~ ^(WAIT_SWITCHOVER)$ ]] ;;
    WAIT_SWITCHOVER)      [[ "$2" =~ ^(WAIT_SWITCHOVER|FINAL_HARVEST_SPLIT|REVOKE_WITHDRAW)$ ]] ;;
    FINAL_HARVEST_SPLIT)  [[ "$2" =~ ^(FINAL_HARVEST_SPLIT|REVOKE_WITHDRAW)$ ]] ;;
    REVOKE_WITHDRAW)      [[ "$2" =~ ^(REVOKE_FEE_CONFIG)$ ]] ;;
    REVOKE_FEE_CONFIG)    [[ "$2" =~ ^(PUBLISH_PROOF)$ ]] ;;
    PUBLISH_PROOF)        [[ "$2" =~ ^(DONE)$ ]] ;;
    DONE)                 [[ "$2" =~ ^(DONE)$ ]] ;;
    *) return 0 ;;
  esac
}
if [[ -n "$prev_state" && -n "$STATE" && "$prev_state" != "$STATE" ]]; then
  if legal_next "$prev_state" "$STATE"; then
    SM_FIELD="$STATE (transición $prev_state→$STATE, ok)"
  else
    SM_FIELD="$STATE (transición ILEGAL $prev_state→$STATE — saltó un paso)"
    red "la máquina de estados saltó un paso: $prev_state→$STATE no es una transición válida"
  fi
elif [[ -n "$STATE" ]]; then
  SM_FIELD="$STATE (sin cambio de estado)"
fi

# ============================================================================
# 5) IDEMPOTENCIA
# ============================================================================
if [[ -n "$resume_line" ]]; then
  IDEM_FIELD="recuperación detectada — ${resume_line#* }"
  yellow "run retomó un split en vuelo (resume inflight); verificar que no duplicó ni saltó"
elif [[ -f "$STATE_DIR/split-inflight" ]]; then
  IDEM_FIELD="split-inflight presente al terminar — plan de split sin cerrar"
  yellow "state/split-inflight sigue presente tras el run; próximo ciclo debe retomarlo"
else
  IDEM_FIELD="OK — sin split en vuelo, vault drenado a 0"
fi

# ============================================================================
# 6) INDEXADOR (getProgramAccounts). No hay contador vivo: se deriva del estado
#    según §5 (IDLE≈1, HARVEST/FINAL≈2, resto 0-1). Reportar, no medir.
# ============================================================================
case "$STATE" in
  IDLE)                             IDX_N=1 ;;
  HARVEST_SPLIT|FINAL_HARVEST_SPLIT) IDX_N=2 ;;
  SET_FEE_ZERO)                     IDX_N=0 ;;
  WAIT_SWITCHOVER)                  IDX_N=0 ;;
  REVOKE_WITHDRAW|REVOKE_FEE_CONFIG) IDX_N=1 ;;
  *)                                IDX_N=0 ;;
esac
[[ -n "$resume_line" ]] && IDX_N=1   # inflight resume salta el getProgramAccounts del harvest
IDX_FIELD="~$IDX_N llamada(s) getProgramAccounts (derivado del estado, sin contador vivo)"

# ============================================================================
# 7) ANOMALÍA vs. falla de harvest conocida
#    Conocidas: dust de redondeo f64 → 'vault not drained' (run #37, ARREGLADO);
#    API GitHub degradada → 504/HTML en harvest.
# ============================================================================
if grep -qi 'not drained' <<<"$RUN_LOG"; then
  ANOM_FIELD="recurrencia — reapareció 'vault not drained' (era el bug de dust f64 del run #37)"
  red "recurrencia de la falla conocida: vault not drained"
elif [[ "$ENDGAME_OUTCOME" == "failure" && -z "$abort_line" && -z "$error_line" ]]; then
  ANOM_FIELD="nueva — el step de endgame falló sin ABORT/ERROR logueado (posible fallo temprano de RPC/entorno)"
  red "endgame step con outcome=failure sin ABORT/ERROR en el log (fallo antes de loguear)"
else
  ANOM_FIELD="N/A"
fi

# Si el endgame step falló pero no lo capturamos arriba, asegúrate del 🔴.
[[ "$ENDGAME_OUTCOME" == "failure" ]] && red "endgame step outcome=failure"

# Si no hubo líneas nuevas y no fue IDLE esperable, marca duda.
if [[ -z "$RUN_LOG" ]]; then
  yellow "el run no agregó líneas al log; no hay datos nuevos que verificar este ciclo"
  [[ -z "$STATE" ]] && SM_FIELD="desconocido (sin línea STATE= en este run)"
fi

# ============================================================================
# SEMÁFORO
# ============================================================================
if (( ${#REDS[@]} > 0 )); then LIGHT="🔴"
elif (( ${#YELLOWS[@]} > 0 )); then LIGHT="🟡"
else LIGHT="🟢"; fi

# Detalle libre
cum_burn="n/a"; cum_dev="n/a"
if [[ -f "$LEDGER" ]]; then
  cum_burn="$(awk -F, '{s+=$3} END{printf "%d", s+0}' "$LEDGER")"
  cum_dev="$(awk -F, '{s+=$4} END{printf "%d", s+0}' "$LEDGER")"
fi
DETAIL="cur_fee=${CUR_FEE:-n/a} up_fee=${UP_FEE:-n/a} vault_raw=${VAULT_RAW:-n/a} mint_withheld=${MINT_WITHHELD:-n/a}; acumulado quemado=$cum_burn dev=$cum_dev (base units)."
if (( ${#REDS[@]} > 0 )); then DETAIL="$DETAIL HALLAZGOS 🔴: $(IFS='; '; echo "${REDS[*]}")."; fi
if (( ${#YELLOWS[@]} > 0 )); then DETAIL="$DETAIL Notas 🟡: $(IFS='; '; echo "${YELLOWS[*]}")."; fi

# ============================================================================
# APPEND (crea cabecera una sola vez; nunca sobrescribe historial)
# ============================================================================
if [[ ! -f "$HEALTH" ]]; then
  {
    echo "# \$ASHEM — Endgame health log"
    echo
    echo "Generado automáticamente por \`scripts/health-report.sh\` al final de cada"
    echo "run del workflow \`endgame.yml\`. **Solo lectura**: reporta salud técnica del"
    echo "mecanismo sin ejecutar ninguna acción correctiva. Cada entrada es un APPEND;"
    echo "el historial nunca se sobrescribe. Este archivo es el puente para monitoreo"
    echo "off-repo (Cowork): se lee sin tocar el log crudo, el Codespace ni ningún secret."
    echo
    echo "---"
  } > "$HEALTH"
fi

{
  echo
  echo "## Endgame health — $TS"
  echo
  echo "**Semáforo:** $LIGHT"
  echo "**Run revisado:** $RUN_URL"
  echo "**Harvest:** $HARVEST_FIELD"
  echo "**Circuit breaker:** $CB_FIELD"
  echo "**Buffer dinámico:** $BUF_FIELD"
  echo "**Máquina de estados:** $SM_FIELD"
  echo "**Idempotencia:** $IDEM_FIELD"
  echo "**Indexador:** $IDX_FIELD"
  echo "**Anomalía vs. falla de harvest conocida:** $ANOM_FIELD"
  echo "**Detalle libre:** $DETAIL"
  echo
  echo "---"
} >> "$HEALTH"

echo "health-report: wrote $LIGHT entry for STATE=${STATE:-?} to $HEALTH"