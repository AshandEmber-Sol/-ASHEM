#!/usr/bin/env bash
#
# bucket-b-prep.sh — Bucket B monthly runbook helper ($ASHEM)
#
# Semi-manual by design: this script is READ-ONLY. It reads on-chain truth,
# applies the floor-check + circuit-breaker, decides the phase, and PREPARES the
# exact command to run. It signs NOTHING and holds NO secrets. You sign the burn
# on the Ledger; then run `close` with the tx signature to append the idempotent
# ledger row and generate the public monthly report.
#
# See ashem-bucket-b-spec.md (mechanism of record) and
# ashem-decision-bucket-b-parametros.md (the 5 closed parameters).
#
# Usage:
#   ./bucket-b-prep.sh prep                 # compute this month's action + print the command
#   ./bucket-b-prep.sh close --sig <SIG>    # verify on-chain, append ledger, write report
#   ./bucket-b-prep.sh status               # show current supply / reserve / phase, no side effects
#
# Requires: bash, curl, jq, spl-token, solana CLI (same toolchain as endgame.sh).
#
set -euo pipefail

# ------------------------------------------------------------------ CONFIG ----
# All values below are public (mint, program, wallet pubkeys, on-chain params).
# No secrets, no keypair paths: signing is done separately on a Ledger.
ASHEM_MINT="${ASHEM_MINT:-BGRvzRVpdPvzHQXPax5MqERsxZLprvWVTvUzpUUUhXot}"
TOKEN_2022_PROGRAM="TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

RESERVE_WALLET="${RESERVE_WALLET:-2vPwdFBLHBriu53vZ9c6fKidtMbdmLssKDB6Xpo4TJSW}"  # Ember Reserve (bucket B, fresh Ledger derivation, 2026-09-09)
# RESERVE_ATA is auto-resolved from RESERVE_WALLET+mint at runtime (see resolve_reserve).
RESERVE_SIGNER="${RESERVE_SIGNER:-usb://ledger?key=4/0}" # Ledger signer for the Reserve (resolved 2026-09-09 by scanning; matches 2vPwd…TJSW). Needs the Ledger attached via usbipd + /dev/hidrawN chmod'd, and a little SOL in the Reserve for the tx fee.
FEEKEY_WALLET="${FEEKEY_WALLET:-HWtS6J76iq8SEqF1g6aBEH6U6tRiWviZqdHDFtE7se5F}"

# Public RPC is fine here: this script only does getTokenSupply / getTokenAccountBalance
# (no getProgramAccounts), so no indexer is needed.
RPC_URL="${ASHEM_RPC_URL:-https://api.mainnet-beta.solana.com}"

DECIMALS=9
FLOOR_TOKENS=300000000                          # endgame circulating floor — NEVER burn below this
MONTHLY_BURN_TRANCHE_TOKENS=15000000            # decision #1 (strategy, 2026-09-09)
LOCK_FEE_PCT=65                                 # decision #3 — % of Fee-Key fees for lock-phase SOL budget
CIRCUIT_BREAKER_PCT=10                          # abort if a single action moves > this % of supply

STATE_DIR="${STATE_DIR:-state}"
LEDGER="$STATE_DIR/bucket-b-ledger.csv"
INFLIGHT="$STATE_DIR/bucket-b-inflight"
SCANNER_URL="https://ashem.xyz/hearth"          # Liquidity Risk Scanner (for the report footer)
# ------------------------------------------------------------------------------

UNIT=$(( 10 ** DECIMALS ))
MONTH="${MONTH:-$(date -u +%Y-%m)}"             # override with MONTH=YYYY-MM for testing

die()  { echo "ERROR: $*" >&2; exit 1; }
note() { echo "  $*" >&2; }

# Format a base-unit integer as an exact UI decimal string (no float involved).
fmt() {
  local base="$1" whole frac
  whole=$(( base / UNIT ))
  frac=$(( base % UNIT ))
  if (( frac == 0 )); then printf '%d' "$whole"
  else printf '%d.%0*d' "$whole" "$DECIMALS" "$frac" | sed 's/0*$//'; fi
}

rpc() { # $1 = JSON-RPC method, $2 = params array (JSON)
  curl -s "$RPC_URL" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}

get_supply_base() { # total mint supply, base units, commitment confirmed
  rpc getTokenSupply "[\"$ASHEM_MINT\",{\"commitment\":\"confirmed\"}]" \
    | jq -er '.result.value.amount' || die "getTokenSupply failed"
}

# Resolve the Reserve's token account (ATA) and balance from owner+mint in one call.
# Sets RESERVE_ATA and RESERVE (base units). If the account doesn't exist yet
# (pre-hop, Reserve not funded) RESERVE_ATA stays empty and RESERVE=0.
resolve_reserve() {
  [[ -n "$RESERVE_WALLET" ]] || die "RESERVE_WALLET is empty (Fase 0 not done yet?)."
  local out
  out=$(rpc getTokenAccountsByOwner \
    "[\"$RESERVE_WALLET\",{\"mint\":\"$ASHEM_MINT\"},{\"encoding\":\"jsonParsed\",\"commitment\":\"confirmed\"}]")
  RESERVE_ATA=$(echo "$out" | jq -r '.result.value[0].pubkey // empty' 2>/dev/null || true)
  if [[ -z "$RESERVE_ATA" ]]; then
    RESERVE=0
  else
    RESERVE=$(echo "$out" | jq -er '.result.value[0].account.data.parsed.info.tokenAmount.amount') \
      || die "could not read reserve balance"
  fi
}

ledger_has_month() { [[ -f "$LEDGER" ]] && grep -q "^$1," "$LEDGER"; }

imin() { (( $1 < $2 )) && echo "$1" || echo "$2"; }

read_chain() {
  SUPPLY=$(get_supply_base)
  resolve_reserve                 # sets RESERVE_ATA + RESERVE
  FLOOR=$(( FLOOR_TOKENS * UNIT ))
  HEADROOM=$(( SUPPLY - FLOOR ))
}

# ------------------------------------------------------------------- STATUS ---
cmd_status() {
  read_chain
  echo "Bucket B — status ($MONTH)"
  echo "  supply:        $(fmt "$SUPPLY") \$ASHEM"
  echo "  floor:         $(fmt "$FLOOR") \$ASHEM"
  echo "  burn headroom: $(fmt "$HEADROOM") \$ASHEM"
  echo "  reserve:       $(fmt "$RESERVE") \$ASHEM  [${RESERVE_ATA:-ATA not created yet — Reserve not funded}]"
  if (( HEADROOM > 0 )); then echo "  phase:         BURN"; else echo "  phase:         LOCK (supply at/below floor)"; fi
}

# --------------------------------------------------------------------- PREP ---
cmd_prep() {
  mkdir -p "$STATE_DIR"
  if ledger_has_month "$MONTH"; then
    echo "Month $MONTH is already closed in the ledger. Nothing to prepare."; exit 0
  fi
  read_chain

  if (( HEADROOM > 0 )); then
    # -------- BURN phase --------
    local tranche burn cb
    tranche=$(( MONTHLY_BURN_TRANCHE_TOKENS * UNIT ))
    burn=$(imin "$tranche" "$HEADROOM")
    burn=$(imin "$burn" "$RESERVE")
    if (( burn <= 0 )); then die "nothing to burn (reserve empty or supply at floor)"; fi

    cb=$(( SUPPLY * CIRCUIT_BREAKER_PCT / 100 ))
    if (( burn > cb )); then
      die "CIRCUIT BREAKER: planned burn $(fmt "$burn") > ${CIRCUIT_BREAKER_PCT}% of supply $(fmt "$SUPPLY"). Aborting (check config)."
    fi

    printf 'BURN,%s' "$burn" > "$INFLIGHT"; echo ",$MONTH" >> "$INFLIGHT"
    cat <<EOF

=== Bucket B — $MONTH — PHASE: BURN ===================================
  supply now:      $(fmt "$SUPPLY") \$ASHEM
  floor:           $(fmt "$FLOOR") \$ASHEM  (headroom $(fmt "$HEADROOM"))
  reserve:         $(fmt "$RESERVE") \$ASHEM
  ---> BURN this month: $(fmt "$burn") \$ASHEM   (tranche $MONTHLY_BURN_TRANCHE_TOKENS, floor/reserve-capped)
  circuit-breaker: OK ($(fmt "$burn") <= $(fmt "$cb"))

  Sign this on the Ledger (burn is fee-free — supply drops by exactly this amount):

    spl-token burn "$RESERVE_ATA" $(fmt "$burn") \\
      --owner "$RESERVE_SIGNER" --fee-payer "$RESERVE_SIGNER" \\
      -p "$TOKEN_2022_PROGRAM" --url "$RPC_URL"

  (The Reserve wallet needs a little SOL for the tx fee. Then run:
     ./bucket-b-prep.sh close --sig <SIGNATURE> )
======================================================================
EOF
  else
    # -------- LOCK phase (activates when supply reaches 300M floor, ~2 years out) --------
    printf 'LOCK,0,%s\n' "$MONTH" > "$INFLIGHT"
    cat <<EOF

=== Bucket B — $MONTH — PHASE: LOCK ==================================
  Supply has reached the 300M floor. The mechanism switches from burn to
  adding + Burn&Earn-locking liquidity. Per spec §3B, the monthly size is
  driven by the SOL budget (decision #3: ${LOCK_FEE_PCT}% of Fee-Key fees this month);
  the \$ASHEM side is DERIVED from the live pool ratio (CPMM is double-sided).

  This leg is intentionally NOT automated (Fee-Key = Ledger + Raydium UI).
  Runbook:
    1. Determine SOL budget = ${LOCK_FEE_PCT}% of fees claimed by Fee-Key this month.
    2. In Raydium (CPMM, full-range, fee tier 0.25%), add that SOL; the UI fixes
       the required \$ASHEM from the Reserve at the current ratio.
    3. Apply Burn & Earn to the position -> Fee Key NFT mints to Fee-Key.
    4. ./bucket-b-prep.sh close --sig <ADD_LIQ_SIG> --lock-sig <BURN_EARN_SIG> \\
         --sol <SOL_ADDED> --ashem <ASHEM_ADDED>
  NOTE: finalize the exact fee-claim read + ratio derivation as we approach the
        floor (Raydium-specific); the burn phase above runs until then.
======================================================================
EOF
  fi
}

# -------------------------------------------------------------------- CLOSE ---
cmd_close() {
  local sig="" lock_sig="" sol="" ashem=""
  while (( $# )); do case "$1" in
    --sig)      sig="$2"; shift 2;;
    --lock-sig) lock_sig="$2"; shift 2;;
    --sol)      sol="$2"; shift 2;;
    --ashem)    ashem="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac; done
  [[ -n "$sig" ]] || die "close needs --sig <SIGNATURE>"
  [[ -f "$INFLIGHT" ]] || die "no inflight plan; run 'prep' first"

  local phase amount inflight_month
  phase=$(cut -d, -f1 "$INFLIGHT")
  amount=$(cut -d, -f2 "$INFLIGHT")
  inflight_month=$(cut -d, -f3 "$INFLIGHT")
  [[ "$inflight_month" == "$MONTH" ]] || die "inflight month ($inflight_month) != current ($MONTH)"
  if ledger_has_month "$MONTH"; then die "month $MONTH already in ledger (idempotency guard)"; fi

  # verify the signature landed
  rpc getSignatureStatuses "[[\"$sig\"],{\"searchTransactionHistory\":true}]" \
    | jq -er '.result.value[0].confirmationStatus' >/dev/null \
    || die "signature $sig not found / not confirmed"

  read_chain
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$STATE_DIR"
  [[ -f "$LEDGER" ]] || echo "month,phase,amount_base,sig,lock_sig,ts" > "$LEDGER"

  local report="$STATE_DIR/bucket-b-report-$MONTH.md" burned="0" added_line
  if [[ "$phase" == "BURN" ]]; then
    burned="$amount"
    echo "$MONTH,BURN,$amount,$sig,,$ts" >> "$LEDGER"
    added_line="Added to locked liquidity:    — (burn phase)"
  else
    echo "$MONTH,LOCK,${ashem:-0},$sig,${lock_sig:-},$ts" >> "$LEDGER"
    added_line="Added to locked liquidity:    ${ashem:-?} \$ASHEM + ${sol:-?} SOL · tx: $sig · Burn&Earn: ${lock_sig:-?}"
  fi

  cat > "$report" <<EOF
\$ASHEM liquidity/burn report — month $MONTH:

Burned this month:            $( [[ "$phase" == BURN ]] && fmt "$burned" || echo "—" ) \$ASHEM$( [[ "$phase" == BURN ]] && echo " · tx: $sig" )
$added_line
Supply now:                   $(fmt "$SUPPLY") (floor 300M)
Ember Reserve holding now:    $(fmt "$RESERVE") \$ASHEM
Liquidity Risk Scanner ratio: (check live) $SCANNER_URL

Not a promise of a fixed schedule or source — funded by the dev fee stream,
pool trading fees, and/or team contributions, month to month.
Verify it yourself: $SCANNER_URL
EOF

  rm -f "$INFLIGHT"
  echo "Ledger row appended and report written: $report"
  echo "----"
  cat "$report"
}

# --------------------------------------------------------------------- MAIN ---
case "${1:-status}" in
  prep)   cmd_prep;;
  close)  shift; cmd_close "$@";;
  status) cmd_status;;
  *) die "usage: $0 {prep|close --sig <SIG>|status}";;
esac