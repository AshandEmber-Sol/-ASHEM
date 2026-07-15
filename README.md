# Ash & Ember ($ASHEM)

Solana memecoin built on the Token-2022 program (spl-token-2022), using only native extensions — no Anchor, no custom contracts.

Initial supply 1,000,000,000 | Decimals 9 | TransferFeeConfig extension (1.5% with a per-transaction cap) | Circulating floor 300,000,000.

Transparency: the Transfer Fee extension does NOT burn tokens by itself — it only withholds a percentage on each transfer. The actual burn is an explicit step executed by a script (fee harvest, burn, and automatic fee shutoff once the 300M floor is reached).

Work in progress. Full documentation of commands, scripts, and the GitHub Action will keep being added to this repository.

## Automated endgame (scripts/endgame.sh)

A single public script runs the entire lifecycle of the burn mechanism,
including its own termination. It runs on a cron (GitHub Actions). Each run reads
the REAL on-chain state, derives a state, and executes at most ONE action:

IDLE -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_BURN -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE

- Dynamic buffer trigger: fee->0 is scheduled at supply <= 300M + (7-day average daily burn x 5 days), because the epoch switchover (~2-4.5 days on mainnet) leaves the burn still running. Documented fallback: DEFAULT_DAILY_BURN in the script while there's no history yet.
- Idempotent: state is NEVER persisted locally; each run derives it from the mint. A run interrupted at any point resumes without duplicating burns or skipping revocations (tested: T4).
- Revocation of both keys is already written in the code: the REVOKE_WITHDRAW and REVOKE_FEE_CONFIG steps in scripts/endgame.sh.

### Local validator test results (32-slot epochs)

- T1: a scheduled fee change DOES execute even if the transfer-fee-config authority is revoked during the switchover. Revocation only blocks new changes.
- T2: harvest + burn reduces supply by exactly the withheld amount.
- T3: full E2E sequence through DONE with both authorities set to None.
- T4: interruption mid-FINAL_HARVEST_BURN -> the next run recovers from on-chain state (covers the vault-has-balance-but-no-withheld branch).
- T5: with a simulated burn rate of 8M/day, the trigger fired at 300M+40M and the final supply stayed >= 300M.

### Key custody (decision)

GitHub Actions secret (option a). Reasons: the workflow is auditable line by line (consistent with "readability as a feature"); the key's blast radius is bounded and public (it can't mint, can't freeze, can't touch LP; worst case = redirect withheld fees or schedule a fee change visible on-chain ~2 epochs before it takes effect); and the key has a scheduled expiration in REVOKE_WITHDRAW/REVOKE_FEE_CONFIG. A separate signing environment (option b) protects the key more but breaks the readability for external auditors, which is the project's core asset.

### Automation (GitHub Actions)

`.github/workflows/endgame.yml` runs `scripts/endgame.sh` every 6 hours (and on demand via workflow_dispatch):

- Required configuration in repo Settings:
  - Public variables: `ASHEM_MINT`, `ASHEM_VAULT`, `ASHEM_RPC_URL`
  - Secret: `ASHEM_AUTHORITY_KEYPAIR` (JSON of the authority keypair; see "Key custody")
- While the variables don't exist yet, the workflow skips execution with a clean exit (it can be committed before the network is configured).
- Every run commits `state/` (supply history + decision/signature log) back to the repo: the full audit trail lives in git history.
- Solana CLI pinned to the version tested locally (v4.0.2).

### Fee split (1.0% burn / 0.5% dev)

The transfer fee stays **1.5% total** for whoever transfers (the 100,000 $ASHEM cap doesn't change). On harvest, the collected fees are SPLIT:

- **2/3 -> burn** (lowers supply toward the 300M floor)
- **1/3 -> dev wallet** (project sustainability, fully transparent on-chain flow)

Rounding rule (quotable): `dev_cut = floor(total/3)`, the remainder goes to `burn_cut`. **Rounding ALWAYS favors the burn, never the dev.**

The dev wallet is a **destination, not an authority**: it signs nothing, has no power over the mint, only receives. No new key was introduced by the split (it uses the existing withdraw-withheld authority). The transfer to the dev pays the 1.5% like any holder (Token-2022 doesn't exempt accounts); the burn is fee-free, so supply drops by exactly `burn_cut`. Once the endgame is reached (0% fee + keys revoked), the flow to the dev dies along with the burn.

Every harvest is logged in `state/harvest-ledger.csv` (`ts,total,burn_cut,dev_cut,burn_sig,dev_sig`), so anyone can add up how much has been burned vs. how much has gone to the dev, without trusting anyone.

State machine states: `IDLE -> HARVEST_SPLIT -> SET_FEE_ZERO -> WAIT_SWITCHOVER -> FINAL_HARVEST_SPLIT -> REVOKE_WITHDRAW -> REVOKE_FEE_CONFIG -> PUBLISH_PROOF -> DONE`.

**RPC requirement:** the harvest step uses `getProgramAccounts` to enumerate accounts with withheld fees. Public RPCs (devnet and mainnet) block that query against the Token-2022 program, so an indexer RPC (e.g., Helius) is required in the `ASHEM_INDEXER_RPC` variable (secret). All other operations use the normal RPC (`ASHEM_RPC_URL`).

Additional required config in repo Settings: public variable `ASHEM_DEV_WALLET` and secret `ASHEM_INDEXER_RPC`.

**CRITICAL — the vault wallet:** `ASHEM_VAULT` must be a DEDICATED token account, empty at the start, used ONLY to collect fees. It must NEVER be the treasury or any account with a real balance: harvest+split sweeps the vault's entire balance. As a safeguard, the script aborts without moving anything if a single harvest would move more than 10% of supply (likely misconfiguration).
