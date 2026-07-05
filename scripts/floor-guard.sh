#!/usr/bin/env bash
# floor-guard.sh - Apaga el transfer fee de $ASHEM cuando el circulante llega al piso.
# Env: MINT (req), FLOOR (def 300000000), RPC_URL, KEYPAIR
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8899}"
MINT="${MINT:?ERROR: define MINT}"
FLOOR="${FLOOR:-300000000}"
KEYPAIR="${KEYPAIR:-$HOME/ashem/keys/ashem-devnet-authority.json}"
PROGRAM_2022="TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

echo "== ASHEM floor-guard =="
echo "RPC=$RPC_URL"
echo "MINT=$MINT"
echo "FLOOR=$FLOOR ASHEM"

SUPPLY="$(spl-token supply "$MINT" --url "$RPC_URL")"
echo "Supply actual: $SUPPLY ASHEM"

ABOVE="$(awk -v s="$SUPPLY" -v f="$FLOOR" 'BEGIN{print (s+0 > f+0)?1:0}')"
if [ "$ABOVE" -eq 1 ]; then
  echo "Supply por encima del piso -> sin cambios."
  exit 0
fi

echo "Supply <= piso ($FLOOR)."
if spl-token display "$MINT" --url "$RPC_URL" | grep -Eiq "(current|upcoming) fee:[[:space:]]*0bps"; then
  echo "El transfer fee ya esta en 0 bps -> nada que hacer."
  exit 0
fi

echo "Apagando transfer fee (0 bps / 0 max)..."
spl-token set-transfer-fee "$MINT" 0 0 \
  --url "$RPC_URL" \
  --program-2022 \
  --fee-payer "$KEYPAIR" \
  --transfer-fee-authority "$KEYPAIR"
echo "Transfer fee apagado. Piso alcanzado."
