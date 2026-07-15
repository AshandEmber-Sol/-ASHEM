# $ASHEM — Fee Split (1.0% burn / 0.5% dev): implemented and verified

**From:** Claude Code session · **Date:** 2026-07-10 · **Commit:** 0286492 on main
**Depends on:** prior infrastructure (harvest + state machine). This was a modification to the harvest plus a corrected gap, not a redesign.

## The 4 confirmations

### 1. Split implemented and verified on devnet
"1% burned, 0.5% sustains development" can now be published with proof. From each harvest: `dev_cut = floor(total/3)` goes to the dev, the rest is burned. Supply drops by EXACTLY what's burned (the burn is fee-free). Verified on-chain:

- **S1 (divisible split):** 45,000 withheld -> 30,000 burned / 15,000 to dev · supply -30,000 exact · exact conservation.
- **S2 (rounding):** withheld not divisible by 3 -> the remainder goes TO THE BURN, never to the dev. Quotable rule: "rounding always favors the burn."
- **S3 (endgame):** the final split happens BEFORE keys are revoked; after revocation, zero flow to the dev.
- **S4 (interruption):** killing the process between the dev payout and the burn, the re-run completes only what's missing, without duplicating the payout.

### 2. Dev wallet: SEPARATE from the authority wallet
Public address: `Bn1g4i66pnYHzftdhkpnzTYunBhBZmFvjCyLJZpuf3bN`
It's purely a transfer destination: signs nothing, has no authority over the mint, only receives. Clean read for an auditor: "this one receives the 0.5%, the other one holds the keys."

### 3. Final state name
`FINAL_HARVEST_BURN` -> renamed to **`FINAL_HARVEST_SPLIT`**. Quote it literally (it appears the same in code and logs).

### 4. No new key from the split
It uses the EXISTING withdraw-withheld authority. Still the same two-key scheme. Revocation is already written in the code:
`scripts/endgame.sh`, **line 162** (`withheld-withdraw --disable`) and **line 166** (`transfer-fee-config --disable`).
NOTE: these line numbers changed from 114/118 in the previous deliverable — update any citation.

## Two things to disclose before an auditor does

- **The dev's 0.5% also pays the 1.5% fee**, like any holder — Token-2022 doesn't exempt accounts. The vault debits exactly `dev_cut`; the dev's account receives it with its 1.5% withheld inside. Narrative in its favor: "the dev gets no special treatment: their cut pays the same fee everyone does."
- **The burn mechanism toward 300M didn't exist in the previous code** (it only burned at the endgame -> supply never dropped -> the trigger was never met). Fixed by adding continuous harvest+split (every 6h). The burn toward the floor is now real.

## Infrastructure finding (impacts mainnet setup)

The harvest needs `getProgramAccounts` to enumerate accounts with withheld fees, and public RPCs (devnet and mainnet) BLOCK that query against Token-2022. An indexer RPC (like Helius) is required as a secret (`ASHEM_INDEXER_RPC`). It's a new dependency and cost for mainnet.

## Safeguard: circuit breaker (impossible to drain the token by mistake)

Continuous harvest+split sweeps the vault's balance. To guard against a misconfiguration (vault pointing at the treasury) or someone sending tokens to the vault by mistake, the script has a fuse: it aborts without moving a single token if one harvest would move more than 10% of supply. Real fees per cycle are tiny; any abnormal amount = likely error, and the script does nothing.

This was found and fixed while testing on devnet: the workflow's first run had the vault misconfigured (pointing at the 1B treasury) and the split swept the whole balance. Devnet only, no value at stake. The fuse now covers that case: verified that with the same catastrophic config, it aborts and leaves supply and treasury intact.

Quotable line: "the mechanism cannot move more than 10% of supply per cycle — it's impossible to drain the token through a misconfiguration."

## Auditability

Every harvest is logged in `state/harvest-ledger.csv` (`ts, total, burn_cut, dev_cut, burn_sig, dev_sig`), committed by the workflow bot. Anyone can add up how much has been burned vs. how much has gone to the dev, without trusting the repo.

**Status:** committed and tested on devnet. No technical blockers for the "total burn -> split" content patch.
