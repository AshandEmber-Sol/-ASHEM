# $ASHEM — Mainnet deployment log

Permanent, auditable record of the $ASHEM token deployment on Solana **mainnet-beta**,
executed **2026-07-26**. Every claim below is independently verifiable on-chain — do not
trust this document, verify it (commands at the bottom).

## Token

| | |
|---|---|
| **Mint (token address)** | `BGRvzRVpdPvzHQXPax5MqERsxZLprvWVTvUzpUUUhXot` |
| Program | Token-2022 (`TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`) |
| Decimals | 9 |
| Supply | 1,000,000,000 (fixed) |
| Transfer fee | 150 bps (1.5%), maximum fee `u64::MAX` (uncapped) |
| Metadata `uri` | `https://gateway.irys.xyz/FWHqfzW53V5j8onsJsapAPqMHfxhjoDeAtafp4z1n2Bb` |
| Logo (image) | `https://gateway.irys.xyz/6QmtaUUniQGwv8JrZRQLhDJEY2Hy47eyRoyfWo1LQytF` |

Both metadata assets are hosted content-addressed on Arweave via Irys (immutable).

## Wallet roster (public keys only)

| Role | Address | Notes |
|---|---|---|
| Treasury | `H6ejVfKrWGrGcb3hLgTtUy9Q3s1rDe7cm9pGhnBncge2` | holds the 1,000,000,000 supply; cold |
| Treasury token account (ATA) | `AS3L8536pt5EidEmLE2XAAeJ2C53YJLMGo7BAuCAHzjj` | where the supply lives |
| Fee/harvest authority ("hot") | `DBj2zRbarj6J1DAnMmb47Wb1saEgLWPK8VFAuZCZFpmJ` | holds transfer-fee-config + withheld-withdraw authorities; used by the off-chain guard; revoked by the guard at end-of-life |
| Vault | `2B2T7z7TNbDSF2gVSPXZT7MGB8JSssnw9C373BZRYVmc` | dedicated, empty fee-collection account, owned by the hot key |
| Dev wallet | `Cxa9MZvh3Hd41Qcrs1zqeBi1Q14mDicnDQHvAorXDv9H` | receives 1/3 of each harvest |

## Process & custody

- All keys were generated and used exclusively on a **local WSL2 (Ubuntu) environment** on the
  owner's own machine. The cloud Codespace was **never opened or used** for any part of this
  deployment. Private keys never left the local machine; seed phrases were backed up offline.
- The deployment made **zero git commits and zero pushes** — no repository was written to during
  the on-chain operations, so there was no vector for a secret to enter version control.
- Executed in **two phases with a verification checkpoint in between**:
  - **Phase 1 (constructive, reversible):** create mint → mint supply → set metadata → reassign the
    fee authorities to the hot key → create the vault. On-chain state verified before proceeding.
  - **Phase 2 (irreversible lockdown):** revoke metadata, metadata-pointer, mint, and freeze
    authorities.
- Procedure follows [`docs/MAINNET-METADATA.md`](MAINNET-METADATA.md), which was validated end-to-end
  on devnet (deploy + harvest) before mainnet.

## Transactions

### Phase 1 — constructive

| Step | Action | Signature |
|---|---|---|
| 1 | create mint (Token-2022: metadata + freeze + transfer-fee) | `RVmi2AQmmPHazwDqbB1BTsftjD2JKnNda5cbS3xJ3fYAvTvzZhGGSsvyPSY31HMyMzpED3bsjzAtMYmuPWTb6Wu` |
| 2a | create treasury ATA | `3gLywFHiNHYWm4YNEv3Lkj5gEBBfQ9P2X7s1uFF4yMBD7UdwxZ68UTm9G5QpPJfTTVZjUiDZ6oHP5ARGMVUvdKaq` |
| 2b | mint 1,000,000,000 | `593jR1aN3mgzdGYKhWEcFnX7vohtbr812X7eYz127vtJU3ifduS8nuEgk34cESZfMJnQ3VcYFwkT41t9M3Lmm5Bv` |
| 3 | initialize metadata | `5X1ANaaUqVfFW35F5gHQLi5jFaDTET7ZVq8uzMEXn4xcvnRh7JEWzmxq6CxDp7PGiMztAA7DfSko95z8fKkq1KEo` |
| 4a | reassign transfer-fee-config → hot | `4Vydguqn8H8Cj7aUTqqax2FRUjDs3gTDptQqBjcLkgabPF7ehooyPbs6sfJoLrBjbqsPxbszvFfFfSMjPUYjbiUW` |
| 4b | reassign withheld-withdraw → hot | `2onLmewmjZgSrp4vkU5nAy5KUyu46or2JrgBTTPMA9iQFcz3kFSLNCjcE9fB9R5vQ4mTo9YmqYCHanXg2efvsVVV` |
| 5 | create vault (owned by hot) | `3SjinTZftmhDU424tEWsaPuAB9Q5W27SndKqF786d4rHgA82z4239c7EGxVvw9L67DBQhvdm2HVohaqd71XDaF2k` |
| 6 | fund hot with 0.03 SOL (future CI fees) | `3fZoHGXGpdNZs9i8LH11PvHgBibAznGm22Bg3CCUUQ2B4Uuk1vkrxQMewk2dP1vpyUiNjx8if5aCzaKciMrMeXRx` |

### Phase 2 — irreversible lockdown (with slots — prove ordering)

| Step | Action | Signature | Slot |
|---|---|---|---|
| — | (metadata initialized, Phase 1 step 3) | `5X1ANaaUqV…` | **435419236** |
| 1 | revoke metadata (content) authority | `57QViBhYuTNisiNySxu8VNMUY4BBFiMWrZ5k5pFHiCtXFDd2tzsBNp6D9zHoMeASDGz2JDJkjSuV2LN5bYG93WmK` | 435420933 |
| 2 | revoke metadata-pointer authority | `3N9mWNTdU7tEbiKzn2vpA5DztzbbxZ9bxkagn8MNQLGf2db3asN9NFuAiU2BfgVeTqLWib24iZonxou7D7tm7u3m` | 435420936 |
| 3 | revoke mint authority | `D8u4mxnXHWkjehDNabnrTDwkiqF6tkRvexQ2NQiSnhyaU1fxng7UdtRGfDzMf4AK3LfGq3sj5JVY41yMMVAz8EU` | 435420940 |
| 4 | revoke freeze authority | `3VBQb5iQQGyQPhD63jRLMGhjfNQWJhDViBe1WowhvAUTozh1et1VdKEEc77c2rwL8pdqfX3vnhLd6AMVMHc5qRA5` | 435420967 |

The metadata was set at slot **435419236**, ~1,731 slots (~12 min) **before** the first revocation,
proving metadata-before-revoke. `initialize-metadata` requires an active mint authority to sign, so
its success is itself proof the mint authority was still live at that point.

## Final on-chain state (verified via `getAccountInfo`, jsonParsed)

```
mintAuthority:                      null
freezeAuthority:                    null
metadataPointer.authority:          null
tokenMetadata.updateAuthority:      null
transferFeeConfigAuthority:         DBj2zRbarj6J1DAnMmb47Wb1saEgLWPK8VFAuZCZFpmJ   (hot — by design)
withdrawWithheldAuthority:          DBj2zRbarj6J1DAnMmb47Wb1saEgLWPK8VFAuZCZFpmJ   (hot — by design)
transferFeeBasisPoints / maximumFee: 150 / 18446744073709551615
supply:                             1000000000000000000
name / symbol / uri:                Ash & Ember / ASHEM / https://gateway.irys.xyz/FWHqfzW53V5j8onsJsapAPqMHfxhjoDeAtafp4z1n2Bb
```

The four revoked authorities are `null` (mint, freeze, metadata-content, metadata-pointer). The two
transfer-fee authorities intentionally remain on the hot key: the off-chain guard (`endgame.sh`)
uses them to harvest/split/burn and revokes them itself at end-of-life.

## Secret scan

`gitleaks` v8.18.4 run on this repository 2026-07-26: **64 commits scanned (git history) + working
tree — no leaks found.** (The deployment wrote nothing to git, so the repo is unchanged from the
prior clean scan of 2026-07-15.)

## Verify it yourself

Current authority state (immediate ground truth, no explorer indexing lag):

```bash
curl -s https://api.mainnet-beta.solana.com -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getAccountInfo","params":["BGRvzRVpdPvzHQXPax5MqERsxZLprvWVTvUzpUUUhXot",{"encoding":"jsonParsed"}]}' \
  | python3 -m json.tool
```

Ordering of the deployment transactions (slot per signature):

```bash
for sig in 5X1ANaaUqVfFW35F5gHQLi5jFaDTET7ZVq8uzMEXn4xcvnRh7JEWzmxq6CxDp7PGiMztAA7DfSko95z8fKkq1KEo \
           57QViBhYuTNisiNySxu8VNMUY4BBFiMWrZ5k5pFHiCtXFDd2tzsBNp6D9zHoMeASDGz2JDJkjSuV2LN5bYG93WmK \
           3N9mWNTdU7tEbiKzn2vpA5DztzbbxZ9bxkagn8MNQLGf2db3asN9NFuAiU2BfgVeTqLWib24iZonxou7D7tm7u3m \
           D8u4mxnXHWkjehDNabnrTDwkiqF6tkRvexQ2NQiSnhyaU1fxng7UdtRGfDzMf4AK3LfGq3sj5JVY41yMMVAz8EU \
           3VBQb5iQQGyQPhD63jRLMGhjfNQWJhDViBe1WowhvAUTozh1et1VdKEEc77c2rwL8pdqfX3vnhLd6AMVMHc5qRA5 ; do
  curl -s https://api.mainnet-beta.solana.com -X POST -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTransaction\",\"params\":[\"$sig\",{\"maxSupportedTransactionVersion\":0}]}" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);r=d.get('result');print((r['slot'] if r else 'NOT FOUND'),'$sig'[:10])"
done
```

## Exact deploy scripts

These are the exact scripts run (local, WSL2). Addresses are the mainnet keypair files under
`~/ashem-keys/mainnet/` on the owner's machine (not in this repo).

### `deploy-mainnet-p1.sh` (Phase 1 — constructive)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/ashem-keys/mainnet

T22="TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
TREASURY="mainnet-treasury.json"
TREASURY_PUB="$(solana-keygen pubkey $TREASURY)"
HOT_PUB="$(solana-keygen pubkey mainnet-hot.json)"
URI="https://gateway.irys.xyz/FWHqfzW53V5j8onsJsapAPqMHfxhjoDeAtafp4z1n2Bb"
NET="-u mainnet-beta"

solana config set --url mainnet-beta --keypair "$PWD/$TREASURY" >/dev/null

spl-token create-token --enable-metadata --enable-freeze \
  --transfer-fee-basis-points 150 --transfer-fee-maximum-fee 18446744073709551615 \
  -p "$T22" --decimals 9 $NET \
  --mint-authority "$TREASURY_PUB" --fee-payer "$TREASURY" \
  mainnet-mint.json
MINT="$(solana-keygen pubkey mainnet-mint.json)"

spl-token create-account "$MINT" --owner "$TREASURY_PUB" --fee-payer "$TREASURY" $NET
spl-token mint "$MINT" 1000000000 --mint-authority "$TREASURY" --fee-payer "$TREASURY" $NET

spl-token initialize-metadata "$MINT" "Ash & Ember" "ASHEM" "$URI" \
  --update-authority "$TREASURY_PUB" --mint-authority "$TREASURY" --fee-payer "$TREASURY" $NET

spl-token authorize "$MINT" transfer-fee-config "$HOT_PUB" --authority "$TREASURY" $NET
spl-token authorize "$MINT" withheld-withdraw "$HOT_PUB" --authority "$TREASURY" $NET

spl-token create-account "$MINT" mainnet-vault.json --owner "$HOT_PUB" --fee-payer "$TREASURY" $NET

solana transfer "$HOT_PUB" 0.03 --keypair "$TREASURY" --allow-unfunded-recipient $NET
```

### `deploy-mainnet-p2.sh` (Phase 2 — irreversible lockdown)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/ashem-keys/mainnet
MINT=BGRvzRVpdPvzHQXPax5MqERsxZLprvWVTvUzpUUUhXot
TREASURY="mainnet-treasury.json"
NET="-u mainnet-beta"
solana config set --url mainnet-beta --keypair "$PWD/$TREASURY" >/dev/null

spl-token authorize "$MINT" metadata --disable --authority "$TREASURY" $NET
spl-token authorize "$MINT" metadata-pointer --disable --authority "$TREASURY" $NET
spl-token authorize "$MINT" mint --disable --authority "$TREASURY" $NET
spl-token authorize "$MINT" freeze --disable --authority "$TREASURY" $NET
```
