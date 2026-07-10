#!/usr/bin/env bash
# =============================================================================
# $ASHEM guard - full lifecycle of the fee mechanism in one public script,
# including its own termination. Runs on a cron (GitHub Actions): one action
# per run, state derived from REAL on-chain data (never trusts local state).
#
# FEE SPLIT: the 1.5% transfer fee is collected (harvest) and SPLIT:
#   burn_cut = 2/3  -> burned (supply drops, drives scarcity toward the floor)
#   dev_cut  = 1/3  -> transferred to the dev wallet (transparent, on-chain)
# Rounding rule (citable): dev_cut = floor(total/3); the remainder goes to
# burn_cut. Rounding ALWAYS favors the burn, never the dev.
# The dev wallet is a DESTINATION, not an authority: signs nothing, has no
# power over the mint, only receives. No new key was introduced for the split
# - the existing withdraw-withheld authority does the harvest.
# Note: burns are fee-free, so supply drops by EXACTLY burn_cut. The dev
# transfer pays the standard 1.5% like any holder (fee withheld in the dev
# account, re-collected next cycle). No exemptions.
#
# States (names appear literally in logs and public posts):
#   IDLE                supply above trigger, nothing withheld to collect
#   HARVEST_SPLIT       collect withheld, send 1/3 to dev, burn 2/3
#   SET_FEE_ZERO        floor+buffer reached: schedule transfer fee -> 0 bps
#   WAIT_SWITCHOVER     0 bps scheduled, waiting epoch switchover (~2 epochs)
#   FINAL_HARVEST_SPLIT last collect+split before revoking (fee already 0)
#   REVOKE_WITHDRAW     revoke withheld-withdraw authority (permanent)
#   REVOKE_FEE_CONFIG   revoke transfer-fee-config authority (permanent)
#   PUBLISH_PROOF       write ENDGAME.md (totals, signatures, mint state)
#   DONE                keys are dead, mechanism finished
#
# Ordering invariant: FINAL_HARVEST_SPLIT strictly before REVOKE_WITHDRAW, or
# residual withheld fees are locked forever. When the fee reaches 0% and the
# keys are revoked, the dev flow dies with the burn - same death date.
#
# Split idempotency: the two money moves (dev transfer, burn) are resumable.
# A run may die between them; the next run reads the vault balance on-chain
# (== total | burn_cut | 0) and finishes exactly the missing move, never
# duplicating. The plan (total/dev_cut/burn_cut) is recorded in state/.
# =============================================================================
set -euo pipefail

MINT="${ASHEM_MINT:?export ASHEM_MINT=<mint address>}"
VAULT="${ASHEM_VAULT:?export ASHEM_VAULT=<dedicated fee-collection token account>}"
DEV_WALLET="${ASHEM_DEV_WALLET:?export ASHEM_DEV_WALLET=<dev wallet, receives 1/3>}"
TOKEN22="TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
UNIT=1000000000                 # 10^decimals (decimals = 9)

FLOOR=300000000                 # hard floor (UI): supply must never END below this
BUFFER_DAYS=5                   # switchover takes up to ~4.5 days on mainnet
DEFAULT_DAILY_BURN=1500000      # conservative fallback until history exists
STATE_DIR="state"
HISTORY="$STATE_DIR/supply-history.csv"   # unix_ts,supply - public, committed
LEDGER="$STATE_DIR/harvest-ledger.csv"    # ts,total,burn_cut,dev_cut,burn_sig,dev_sig
INFLIGHT="$STATE_DIR/split-inflight"      # in-progress split plan (idempotency)
LOGF="$STATE_DIR/endgame-log.txt"         # every decision + signature - public
PROOF="ENDGAME.md"

mkdir -p "$STATE_DIR"
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOGF"; }
sig_of() { awk '/^Signature:/{print $2; exit}'; }
acct_raw() { curl -sf "$RPC" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getTokenAccountBalance","params":["'"$1"'",{"commitment":"confirmed"}]}' | jq -r '.result.value.amount // "0"'; }
raw_to_ui() { local r="$1"; printf '%d.%09d' "$(( r / UNIT ))" "$(( r % UNIT ))"; }

# token accounts of this mint still holding withheld fees (jsonParsed RPC scan)
withheld_sources() {
  curl -sf "$INDEXER_RPC" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"getProgramAccounts","params":["'"$TOKEN22"'",{"commitment":"confirmed","encoding":"jsonParsed","filters":[{"memcmp":{"offset":0,"bytes":"'"$MINT"'"}}]}]}' |
  jq -r '.result[] | select([.account.data.parsed.info.extensions[]? | select(.extension=="transferFeeAmount") | (.state.withheldAmount // 0 | tonumber)] | add > 0) | .pubkey'
}

# harvest all withheld into the vault, then split it 2/3 burn : 1/3 dev.
# Idempotent: uses state/split-inflight for the plan and the on-chain vault
# balance as the source of truth for which move still needs doing.
do_split() {
  local ctx="$1" srcs vraw total dev_cut burn_cut dev_sig burn_sig
  if [[ -f "$INFLIGHT" ]]; then
    read -r total dev_cut burn_cut < "$INFLIGHT"
    log "$ctx resume inflight total=$total dev_cut=$dev_cut burn_cut=$burn_cut"
  else
    srcs="$(withheld_sources || true)"
    if [[ -n "$srcs" || "${MINT_WITHHELD:-0}" -ne 0 ]]; then
      WSIG="$(spl-token withdraw-withheld-tokens "$VAULT" $srcs --include-mint | sig_of)"
      log "$ctx harvest ok withdraw_sig=$WSIG"
    fi
    vraw="$(acct_raw "$VAULT")"
    if [[ "${vraw:-0}" -eq 0 ]]; then log "$ctx nothing to split (vault empty)"; return 0; fi
    total="$vraw"; dev_cut=$(( total / 3 )); burn_cut=$(( total - dev_cut ))
    printf '%s %s %s\n' "$total" "$dev_cut" "$burn_cut" > "$INFLIGHT"
    log "$ctx planned total=$total burn_cut=$burn_cut dev_cut=$dev_cut (rounding favors burn)"
  fi

  vraw="$(acct_raw "$VAULT")"; dev_sig=already; burn_sig=already
  if [[ "$vraw" -eq "$total" ]]; then
    if (( dev_cut > 0 )); then
      dev_sig="$(spl-token transfer "$MINT" "$(raw_to_ui "$dev_cut")" "$DEV_WALLET" --from "$VAULT" --fund-recipient --allow-unfunded-recipient | sig_of)"
    else dev_sig=skipped_zero; fi
    burn_sig="$(spl-token burn "$VAULT" "$(raw_to_ui "$burn_cut")" | sig_of)"
  elif [[ "$vraw" -eq "$burn_cut" ]]; then
    burn_sig="$(spl-token burn "$VAULT" "$(raw_to_ui "$burn_cut")" | sig_of)"
  elif [[ "$vraw" -ne 0 ]]; then
    log "ERROR: $ctx unexpected vault balance=$vraw (total=$total burn_cut=$burn_cut) - manual review"; exit 1
  fi

  vraw="$(acct_raw "$VAULT")"
  [[ "${vraw:-0}" -eq 0 ]] || { log "ERROR: $ctx vault not drained (=$vraw)"; exit 1; }
  rm -f "$INFLIGHT"
  echo "$(date -u +%FT%TZ),$total,$burn_cut,$dev_cut,$burn_sig,$dev_sig" >> "$LEDGER"
  log "$ctx ok total=$total burn_cut=$burn_cut dev_cut=$dev_cut burn_sig=$burn_sig dev_sig=$dev_sig new_supply=$(spl-token supply "$MINT")"
}

# ---- on-chain reads ---------------------------------------------------------
INFO="$(spl-token display "$MINT")"
SUPPLY="$(spl-token supply "$MINT" | cut -d. -f1)"
CUR_FEE="$(awk -F': *' '/Current fee/{gsub(/bps/,"",$2); print $2}' <<<"$INFO")"
UP_FEE="$(awk -F': *' '/Upcoming fee/{gsub(/bps/,"",$2); print $2}' <<<"$INFO")"
CFG_AUTH="$(awk -F': *' '/Config authority/{print $2}' <<<"$INFO")"
WD_AUTH="$(awk -F': *' '/Withdrawal authority/{print $2}' <<<"$INFO")"
MINT_WITHHELD="$(awk -F': *' '/Withheld fees/{print $2}' <<<"$INFO" | cut -d. -f1)"
RPC="$(solana config get | awk '/RPC URL/{print $3}')"
INDEXER_RPC="${ASHEM_INDEXER_RPC:-$RPC}"
VRAW="$(acct_raw "$VAULT")"

# ---- dynamic trigger buffer -------------------------------------------------
NOW="$(date +%s)"
echo "$NOW,$SUPPLY" >> "$HISTORY"
BUFFER="$(awk -F, -v now="$NOW" -v sup="$SUPPLY" -v days="$BUFFER_DAYS" -v def="$DEFAULT_DAILY_BURN" '
  !reft && $1 >= now-604800 && $1 < now { reft=$1; refs=$2 }
  END { rate=def; if (reft && now-reft>=3600){ r=(refs-sup)/((now-reft)/86400); if(r>0) rate=r } printf "%d", rate*days }' "$HISTORY")"
TRIGGER=$(( FLOOR + BUFFER ))

# ---- derive state from chain ------------------------------------------------
STATE=IDLE
if [[ "$CFG_AUTH" == *"not set"* && "$WD_AUTH" == *"not set"* ]]; then
  STATE=PUBLISH_PROOF; [[ -f "$PROOF" ]] && STATE=DONE
elif [[ "$CUR_FEE" != 0 && "${UP_FEE:-$CUR_FEE}" != 0 ]]; then
  if (( SUPPLY <= TRIGGER )); then
    STATE=SET_FEE_ZERO
  elif [[ -n "$(withheld_sources || true)" || "${MINT_WITHHELD:-0}" -ne 0 || "${VRAW:-0}" -ne 0 || -f "$INFLIGHT" ]]; then
    STATE=HARVEST_SPLIT
  fi
elif [[ "$CUR_FEE" != 0 ]]; then
  STATE=WAIT_SWITCHOVER
else
  if [[ -n "$(withheld_sources || true)" || "${MINT_WITHHELD:-0}" -ne 0 || "${VRAW:-0}" -ne 0 || -f "$INFLIGHT" ]]; then
    STATE=FINAL_HARVEST_SPLIT
  elif [[ "$WD_AUTH" != *"not set"* ]]; then STATE=REVOKE_WITHDRAW
  else STATE=REVOKE_FEE_CONFIG; fi
fi

log "STATE=$STATE supply=$SUPPLY floor=$FLOOR buffer=$BUFFER trigger=$TRIGGER cur_fee=${CUR_FEE}bps up_fee=${UP_FEE:-n/a}bps vault_raw=${VRAW:-0} mint_withheld=${MINT_WITHHELD:-0}"

# ---- one action per run -----------------------------------------------------
case "$STATE" in
  IDLE) ;;
  HARVEST_SPLIT) do_split HARVEST_SPLIT ;;
  SET_FEE_ZERO)
    SIG="$(spl-token set-transfer-fee "$MINT" 0 0 | sig_of)"
    spl-token display "$MINT" | grep -q "Upcoming fee: 0bps" || { log "ERROR: SET_FEE_ZERO not confirmed on-chain"; exit 1; }
    log "SET_FEE_ZERO ok sig=$SIG (activates at epoch switchover)";;
  WAIT_SWITCHOVER)
    log "WAIT_SWITCHOVER current fee still ${CUR_FEE}bps, 0bps pending";;
  FINAL_HARVEST_SPLIT) do_split FINAL_HARVEST_SPLIT ;;
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
      echo; echo "Generated: $(date -u +%FT%TZ)"
      echo; echo "Final supply: $(spl-token supply "$MINT")"
      echo "Dev wallet (received 1/3 of every harvest): $DEV_WALLET"
      if [[ -f "$LEDGER" ]]; then
        echo "Cumulative burned (base units): $(awk -F, '{s+=$3} END{print s+0}' "$LEDGER")"
        echo "Cumulative to dev (base units): $(awk -F, '{s+=$4} END{print s+0}' "$LEDGER")"
      fi
      echo; echo '```'; spl-token display "$MINT"; echo '```'
      echo; echo "## Full action log (every decision, every signature)"
      echo '```'; cat "$LOGF"; echo '```'
    } > "$PROOF"
    log "PUBLISH_PROOF ok wrote $PROOF";;
  DONE) log "DONE nothing to do";;
esac
