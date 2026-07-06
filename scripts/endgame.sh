#!/usr/bin/env bash
# =============================================================================
# $ASHEM endgame guard - the entire lifecycle of the burn mechanism in one
# public script, including its own termination. Runs on a cron (GitHub Actions).
#
# Every run: (1) read REAL on-chain state - never trust local state between
# runs; (2) derive the machine state below; (3) execute at most ONE action,
# confirm it on-chain, exit. Interrupted runs resume naturally (idempotent).
#
# States (these names appear literally in logs and public posts):
#   IDLE                supply above trigger, nothing to do
#   SET_FEE_ZERO        floor+buffer reached: schedule transfer fee -> 0 bps
#   WAIT_SWITCHOVER     0 bps scheduled, waiting epoch switchover (~2 epochs)
#   FINAL_HARVEST_BURN  fee inactive: withdraw ALL withheld fees and burn them
#   REVOKE_WITHDRAW     revoke withheld-withdraw authority (permanent)
#   REVOKE_FEE_CONFIG   revoke transfer-fee-config authority (permanent)
#   PUBLISH_PROOF       write ENDGAME.md (signatures, final supply, mint state)
#   DONE                keys are dead, mechanism finished
#
# Ordering invariant: FINAL_HARVEST_BURN strictly before REVOKE_WITHDRAW,
# or residual withheld fees are locked forever.
# Verified on local validator (test T1): a scheduled fee change STILL
# activates after transfer-fee-config is revoked; revocation only blocks
# new changes. See README for how to reproduce.
# =============================================================================
set -euo pipefail

MINT="${ASHEM_MINT:?export ASHEM_MINT=<mint address>}"
VAULT="${ASHEM_VAULT:?export ASHEM_VAULT=<dedicated, fee-only token account>}"
TOKEN22="TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

FLOOR=300000000          # hard floor (UI): supply must never END below this
BUFFER_DAYS=5            # switchover takes up to ~4.5 days on mainnet
DEFAULT_DAILY_BURN=1500000  # conservative fallback until history exists (see README)
STATE_DIR="state"
HISTORY="$STATE_DIR/supply-history.csv"  # unix_ts,supply - public, committed
LOGF="$STATE_DIR/endgame-log.txt"        # every decision + signature - public
PROOF="ENDGAME.md"

mkdir -p "$STATE_DIR"
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOGF"; }
sig_of() { awk '/^Signature:/ && !s {sig=$2; s=1} END{print sig}'; }

# ---- on-chain reads ---------------------------------------------------------
INFO="$(spl-token display "$MINT")"
SUPPLY="$(spl-token supply "$MINT" | cut -d. -f1)"
CUR_FEE="$(awk -F': *' '/Current fee/{gsub(/bps/,"",$2); print $2}' <<<"$INFO")"
UP_FEE="$(awk -F': *' '/Upcoming fee/{gsub(/bps/,"",$2); print $2}' <<<"$INFO")"
CFG_AUTH="$(awk -F': *' '/Config authority/{print $2}' <<<"$INFO")"
WD_AUTH="$(awk -F': *' '/Withdrawal authority/{print $2}' <<<"$INFO")"
MINT_WITHHELD="$(awk -F': *' '/Withheld fees/{print $2}' <<<"$INFO" | cut -d. -f1)"
RPC="$(solana config get | awk '/RPC URL/{print $3}')"
VBAL="$(spl-token balance --address "$VAULT" 2>/dev/null | cut -d. -f1 || echo 0)"

# token accounts of this mint still holding withheld fees (jsonParsed RPC scan)
withheld_sources() {
  curl -sf "$RPC" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getProgramAccounts","params":["'"$TOKEN22"'",{"encoding":"jsonParsed","filters":[{"memcmp":{"offset":0,"bytes":"'"$MINT"'"}}]}]}' |
  jq -r '.result[] | select([.account.data.parsed.info.extensions[]? | select(.extension=="transferFeeAmount") | (.state.withheldAmount // 0 | tonumber)] | add > 0) | .pubkey'
}

# ---- Requirement 1: dynamic trigger buffer ----------------------------------
# buffer = (avg daily burn over last 7d) * BUFFER_DAYS. Burning continues
# during the switchover window, so we must fire BEFORE reaching the floor.
NOW="$(date +%s)"
echo "$NOW,$SUPPLY" >> "$HISTORY"
BUFFER="$(awk -F, -v now="$NOW" -v sup="$SUPPLY" -v days="$BUFFER_DAYS" -v def="$DEFAULT_DAILY_BURN" '
  !reft && $1 >= now-604800 && $1 < now { reft=$1; refs=$2 }
  END {
    rate = def
    if (reft && now-reft >= 3600) { r = (refs-sup)/((now-reft)/86400); if (r > 0) rate = r }
    printf "%d", rate*days
  }' "$HISTORY")"
TRIGGER=$((FLOOR + BUFFER))

# ---- derive state from chain -------------------------------------------------
STATE=IDLE
if [[ "$CFG_AUTH" == *"not set"* && "$WD_AUTH" == *"not set"* ]]; then
  STATE=PUBLISH_PROOF; [[ -f "$PROOF" ]] && STATE=DONE
elif [[ "$CUR_FEE" != 0 && "${UP_FEE:-$CUR_FEE}" != 0 ]]; then
  if (( SUPPLY <= TRIGGER )); then STATE=SET_FEE_ZERO; fi
elif [[ "$CUR_FEE" != 0 ]]; then
  STATE=WAIT_SWITCHOVER
else
  SRCS="$(withheld_sources || true)"
  if [[ -n "$SRCS" || "${MINT_WITHHELD:-0}" -ne 0 || "${VBAL:-0}" -ne 0 ]]; then STATE=FINAL_HARVEST_BURN
  elif [[ "$WD_AUTH" != *"not set"* ]]; then STATE=REVOKE_WITHDRAW
  else STATE=REVOKE_FEE_CONFIG; fi
fi

log "STATE=$STATE supply=$SUPPLY floor=$FLOOR buffer=$BUFFER trigger=$TRIGGER cur_fee=${CUR_FEE}bps up_fee=${UP_FEE:-n/a}bps mint_withheld=${MINT_WITHHELD:-0}"

# ---- one action per run -------------------------------------------------------
case "$STATE" in
  IDLE) ;;
  SET_FEE_ZERO)
    SIG="$(spl-token set-transfer-fee "$MINT" 0 0 | sig_of)"
    spl-token display "$MINT" | grep -q "Upcoming fee: 0bps" || { log "ERROR: SET_FEE_ZERO not confirmed on-chain"; exit 1; }
    log "SET_FEE_ZERO ok sig=$SIG (activates at epoch switchover)";;
  WAIT_SWITCHOVER)
    log "WAIT_SWITCHOVER current fee still ${CUR_FEE}bps, 0bps pending";;
  FINAL_HARVEST_BURN)
    SRCS="$(withheld_sources || true)"
    SIG=none
    if [[ -n "$SRCS" || "${MINT_WITHHELD:-0}" -ne 0 ]]; then SIG="$(spl-token withdraw-withheld-tokens "$VAULT" $SRCS --include-mint | sig_of)"; fi
    BAL="$(spl-token balance --address "$VAULT")"
    BURN_SIG=none
    if awk -v b="$BAL" 'BEGIN{exit (b>0)?0:1}'; then
      BURN_SIG="$(spl-token burn "$VAULT" "$BAL" | sig_of)"
    fi
    [[ -z "$(withheld_sources || true)" ]] || { log "ERROR: withheld remains after harvest"; exit 1; }
    spl-token display "$MINT" | grep -qE "Withheld fees: 0(\.0+)?$" || { log "ERROR: mint withheld not zero"; exit 1; }
    log "FINAL_HARVEST_BURN ok withdraw_sig=$SIG burn_sig=$BURN_SIG burned=$BAL new_supply=$(spl-token supply "$MINT")";;
  REVOKE_WITHDRAW)
    SIG="$(spl-token authorize "$MINT" withheld-withdraw --disable | sig_of)"
    spl-token display "$MINT" | grep -q "Withdrawal authority: (not set)" || { log "ERROR: REVOKE_WITHDRAW not confirmed"; exit 1; }
    log "REVOKE_WITHDRAW ok sig=$SIG - withheld-withdraw authority is gone forever";;
  REVOKE_FEE_CONFIG)
    SIG="$(spl-token authorize "$MINT" transfer-fee-config --disable | sig_of)"
    spl-token display "$MINT" | grep -q "Config authority: (not set)" || { log "ERROR: REVOKE_FEE_CONFIG not confirmed"; exit 1; }
    log "REVOKE_FEE_CONFIG ok sig=$SIG - transfer-fee-config authority is gone forever";;
  PUBLISH_PROOF)
    { echo "# \$ASHEM ENDGAME - proof of termination"
      echo
      echo "Generated: $(date -u +%FT%TZ)"
      echo
      echo "Final supply: $(spl-token supply "$MINT")"
      echo
      echo '```'
      spl-token display "$MINT"
      echo '```'
      echo
      echo "## Full action log (every decision, every signature)"
      echo '```'
      cat "$LOGF"
      echo '```'
    } > "$PROOF"
    log "PUBLISH_PROOF ok wrote $PROOF";;
  DONE)
    log "DONE nothing to do";;
esac
