# $ASHEM — Project technical status

**Last updated:** 2026-07-09
**Repo:** AshandEmber-Sol/-ASHEM

## 1. Summary

The full token mechanism (creation, automated burn, buffer-aware shutoff, endgame with key revocation, and cron automation) is built, tested on a local validator (T1-T5), and rehearsed end-to-end against real devnet in GitHub Actions. Zero technical blockers. Only pending item: mainnet deployment (business decision + distribution/LP).

Design principle respected: zero custom on-chain programs, zero Anchor. Everything relies on native Token-2022 extensions + readable off-chain scripts.

## 2. Token parameters

| Parameter | Value |
|---|---|
| Program | Token-2022 (TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb) |
| Initial supply | 1,000,000,000 |
| Decimals | 9 |
| Transfer fee | 150 bps (1.5%) |
| Max fee per tx | 100,000 $ASHEM |
| Circulating floor | 300,000,000 (30%) |
| Mint authority | Revoked (fixed supply) |
| Freeze authority | Revoked |

## 3. On-chain DEVNET state (verified)

> Devnet addresses (ephemeral, no value). Everything gets recreated with a new wallet on mainnet, and addresses change.

| Item | Address |
|---|---|
| Mint | H6cpRwEW8AxQwfWnP4iun2jWgCP2Smdn2zprMFtHuvUu |
| Treasury (ATA) | 8Z1YyMmHHUMmtGCutNFhwqvSgGCWfy7tXsRBeuaYPeZz |
| Authority wallet (devnet) | DFPuDWketoZJqeuHkWL2Ev7JM76ism1FXTjWnK4VVhaV |

State read on-chain: supply 1B, fee 150bps, cap 100k, mint/freeze authority not set, config + withdraw authority on the dedicated wallet, withheld 0.

## 4. Burn architecture (the honest version)

Token-2022's transfer fee does NOT burn or reduce supply by itself — it only withholds a % on each transfer. The actual burn is an explicit scripted step:

    transfer fee withholds 1.5% -> harvest of withheld fees -> burn (THIS is what lowers supply)
    -> once the floor is reached: turn off the fee -> final burn -> revoke both keys -> publish proof

Everything lives in scripts/endgame.sh, a state machine that on every run reads the real on-chain state (never trusts local state), infers where it stands, and executes ONE single action:

    IDLE -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_BURN
    -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE

State names appear literally in the code and in the logs.

## 5. Test results (local validator, accelerated epochs)

| Test | What it validates | Result |
|---|---|---|
| T1 | The scheduled switchover (fee->0) executes even if the config authority is revoked during the window | OK (2 times) |
| T2 | Harvest + burn reduces supply by exactly the amount burned | OK |
| T3 | Full E2E sequence through DONE, both authorities at None | OK |
| T4 | Interruption mid-burn -> recovery without duplicating or skipping steps | OK |
| T5 | Dynamic buffer triggers at floor+buffer and final supply stays >= 300M | OK (final 303,899,995) |

## 6. Real DEVNET rehearsal (run #9, GitHub Actions, success)

The workflow ran the full cycle against the real devnet mint. Log:

    STATE=IDLE supply=1000000000 floor=300000000 buffer=7500000
    trigger=307500000 cur_fee=150bps mint_withheld=0

It correctly read the real on-chain state and decided IDLE (correct, supply >> floor). The secret decrypted and signed correctly; the commit step wrote state/ back to the repo. The 7.5M buffer is the conservative fallback (DEFAULT_DAILY_BURN 1.5M/day x 5) while there's no history yet.

## 7. Automation and custody

- Workflow: .github/workflows/endgame.yml, cron every 6h (0 */6 * * *) + manual trigger. Solana CLI pinned to v4.0.2. Skips cleanly if variables are missing.
- Custody: option (a), GitHub Actions secret. The key only exists during each run. Bounded, public blast radius: it CANNOT mint, CANNOT freeze, CANNOT touch LP; worst case = redirect withheld fees or schedule a fee change visible on-chain ~2 epochs (2-4.5 days) before it applies. It has a scheduled expiration built into the script.
- Auditability: every run commits state/ (supply history + decision/signature log). The full history lives in git.

## 8. Talking points for the thread

1. T1 confirmed: once scheduled, the fee shutoff is executed by the protocol even if we burn the key.
2. Custody: option (a), documented in the README.
3. Dynamic buffer implemented: upholds "hard floor at 300M".
4. Revocation already written: scripts/endgame.sh, lines 114 (withdraw-withheld) and 118 (transfer-fee-config).

## 9. Honesty caveats (state these first)

- There are TWO active authorities, not "one": fee-config authority and withdraw-withheld authority, both on the dedicated wallet.
- The burn is a verifiable promise, not a protocol guarantee: the withdraw authority could technically redirect fees. Mitigation: every harvest/withdraw/burn is public and supply is auditable.
- WAIT_SWITCHOVER with real epochs: tested locally (T1), but its first live run (epochs ~2 days) will happen when real supply hits the trigger on mainnet.

## 10. Pending (strategy decisions, not engineering)

1. Mainnet deployment: new dedicated wallet + real SOL (~0.02) + recreate the mint with already-validated commands + update the repo's variables + load the new key's secret with maximum care.
2. Distribution / liquidity (LP).
3. Launch timing and thread publication.

Technical blockers: none.
