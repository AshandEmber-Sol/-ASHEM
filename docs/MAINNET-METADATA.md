# On-chain token metadata — mainnet procedure

Status: not yet run on mainnet. Verified on devnet: the metadata flow on rehearsal mint
`6Y2EHSvhZyzJE6wESZcAKtKzKX37Ex3DgY1JMTipM3Cd` (2026-07-15), and the transfer-fee configuration
(150 bps, uncapped) on rehearsal mint `LhghiS2pAdbbCK4hR97sRAnPkvbHWoiXrPdqdeQDDBH` (2026-07-17).

## Why native Token-2022 metadata, not classic Metaplex

The current devnet mint (`H6cpRwEW8AxQwfWnP4iun2jWgCP2Smdn2zprMFtHuvUu`) was created without the
Metadata Pointer extension, so it can't use native metadata — that's a dead end specific to that
mint. For the **mainnet mint (not created yet)**, use the native Token-2022 Metadata Pointer +
Token Metadata extension instead of classic Metaplex Token Metadata:

- No external program or separate account — the metadata lives inside the mint itself. Consistent
  with the "zero custom program" principle already applied to Raydium (an already-deployed,
  standard program is fine; a bespoke one is not).
- Every mutability point (name/symbol/uri authority, and the pointer's own authority — see below)
  is closeable in the exact same script that mints and revokes mint/freeze authority. No fourth key
  living in a separate program to remember about later.

## The two-authority gotcha (found during the devnet rehearsal)

Token-2022 metadata has **two separate authority fields**, not one:

| Field | Controls | Disable command |
|---|---|---|
| `tokenMetadata.updateAuthority` | Editing name / symbol / uri | `spl-token authorize <mint> metadata --disable` |
| `metadataPointer.authority` | Where the metadata pointer points (could be redirected to a different account entirely) | `spl-token authorize <mint> metadata-pointer --disable` |

Missing the second one leaves a real way to swap out the token's displayed identity even after the
first authority is gone. Both must be disabled for "nobody can ever change anything" to be literally
true.

**Also learned:** the `Initialize` instruction (`spl-token initialize-metadata`) rejects
`--update-authority 11111111111111111111111111111111` (System Program / null) directly — the
interface requires a real authority at creation time. The fix is not "leave it mutable a bit
longer"; it's initializing with the real authority and disabling it in the **next command of the
same script**, with no manual step and no gap where someone could act on it.

## Transfer fee extension

The mint is created with the Token-2022 Transfer Fee extension enabled (step 1). Transfer Fee must
be enabled at mint creation — unlike most extensions it cannot be added afterward. This is the
extension that collects the 1.5% fee the harvest → split → burn mechanism (`endgame.sh`) runs on.

Two authorities come with it, and `endgame.sh` already expects them and eventually revokes them at
end-of-life (`REVOKE_WITHDRAW`, `REVOKE_FEE_CONFIG` states — see the script's own header comment):

| Authority | Controls | `spl-token authorize` name |
|---|---|---|
| `transferFeeConfigAuthority` | Can change the fee rate/cap later | `transfer-fee-config` |
| `withdrawWithheldAuthority` | Can collect (`withdraw-withheld-tokens`) the fees held in token accounts | `withheld-withdraw` |

`spl-token create-token` (5.5.0) has no explicit flags for these — it sets **both to the fee payer**
(the mint authority) automatically at creation. They **stay active** and are intentionally *not*
revoked by this document; `endgame.sh` revokes them later, once supply has wound down to the floor.
Revoking them here would kill the fee mechanism before it ran. (Confirmed on the 2026-07-17 devnet
rehearsal: both defaulted to the authority wallet.)

**Fee value:** 150 basis points (1.5%).

**Max fee (cap):** the design requires the fee to always be exactly 1.5% of the transfer amount,
uncapped — any finite cap would undercharge large transfers and break the "rounding always favors
the burn" invariant `endgame.sh` relies on. Pass `u64::MAX` in base units (`18446744073709551615`)
to `--transfer-fee-maximum-fee` (the flag takes raw base units, not a UI-scaled amount) for an
effectively uncapped fee. (Confirmed on the 2026-07-17 devnet rehearsal: `create-token` accepts
`u64::MAX`, stores it as the raw base-unit cap, and a 100,000-token transfer withheld exactly 1,500 —
a proportional 1.5% with no cap.)

## Asset hosting

The metadata `uri` points to a JSON file (`{name, symbol, description, image}`), and `image` in turn
points to the logo. Both must be hosted **content-addressed** (Arweave via Irys, not GitHub or any
mutable host) — otherwise the on-chain uri is immutable but what it resolves to isn't, which quietly
breaks the "nothing can change" guarantee. Devnet rehearsal used:

```bash
irys upload <logo.png> -n devnet -t solana -w <authority-keypair> --provider-url https://api.devnet.solana.com
irys upload <metadata.json> -n devnet -t solana -w <authority-keypair> --provider-url https://api.devnet.solana.com
```

For mainnet: same commands with `-n mainnet` and `--provider-url <mainnet RPC>`, funded via
`irys fund <lamports> -n mainnet ...` from the mainnet authority wallet (real SOL, budget small —
a logo + JSON is a few KB).

## Procedure (7 steps, 4 disable calls)

Order matters: `initialize-metadata` must sign with the mint authority, so it has to run before
mint authority is revoked (step 6). Freeze authority (step 7) can be revoked any time after minting.
The 4 disable calls here cover metadata + mint + freeze only — `transfer-fee-config` and
`withheld-withdraw` (set to the fee payer in step 1) are deliberately left active; `endgame.sh`
revokes those later, at end-of-life.

```bash
AUTH=<mainnet-authority-keypair>
MINT_KP=<mainnet-mint-keypair>

# 1. Create mint with Metadata Pointer + Token Metadata extension, freeze enabled,
#    and Transfer Fee enabled (1.5%, uncapped — see "Transfer fee extension" above).
#    The two fee authorities (config + withdraw-withheld) default to the fee payer ($AUTH).
spl-token create-token --enable-metadata --enable-freeze \
  --transfer-fee-basis-points 150 \
  --transfer-fee-maximum-fee 18446744073709551615 \
  -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb \
  --decimals 9 -u mainnet-beta \
  --mint-authority $(solana-keygen pubkey $AUTH) \
  --fee-payer $AUTH \
  $MINT_KP

MINT=$(solana-keygen pubkey $MINT_KP)

# 2. Create the authority's token account, then mint the full supply into it
#    (create-token does not auto-create it in spl-token 5.5.0)
spl-token create-account $MINT --fee-payer $AUTH -u mainnet-beta
spl-token mint $MINT 1000000000 --mint-authority $AUTH --fee-payer $AUTH -u mainnet-beta

# 3. Write name/symbol/uri (temporary real authority — same script, no gap)
spl-token initialize-metadata $MINT "Ash & Ember" "ASHEM" "<irys-metadata-json-uri>" \
  --update-authority $(solana-keygen pubkey $AUTH) \
  --mint-authority $AUTH \
  --fee-payer $AUTH \
  -u mainnet-beta

# 4. Disable metadata content authority
spl-token authorize $MINT metadata --disable --authority $AUTH -u mainnet-beta

# 5. Disable metadata pointer authority (the one that's easy to forget)
spl-token authorize $MINT metadata-pointer --disable --authority $AUTH -u mainnet-beta

# 6. Revoke mint authority (supply now fixed)
spl-token authorize $MINT mint --disable --authority $AUTH -u mainnet-beta

# 7. Revoke freeze authority (nobody can ever freeze an account)
spl-token authorize $MINT freeze --disable --authority $AUTH -u mainnet-beta
```

## Verification (don't trust CLI output alone)

Query the mint directly and confirm the four disabled authority fields are `null`, plus the correct
name/symbol/uri, plus the transfer-fee config matching what was set in step 1:

```bash
curl -s <mainnet RPC> -X POST -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0","id":1,"method":"getAccountInfo",
  "params":["'"$MINT"'", {"encoding":"jsonParsed"}]
}'
```

Expect: `mintAuthority: null`, `freezeAuthority: null`,
`metadataPointer.state.authority: null`, `tokenMetadata.state.updateAuthority: null`,
`tokenMetadata.state.name/symbol/uri` matching what was set in step 3, and
`transferFeeConfig.newerTransferFee.transferFeeBasisPoints: 150` with `maximumFee:
18446744073709551615` and `transferFeeConfigAuthority`/`withdrawWithheldAuthority` both equal to the
mainnet authority pubkey (not null — those stay active by design).

## Devnet rehearsal reference

Metadata mint: `6Y2EHSvhZyzJE6wESZcAKtKzKX37Ex3DgY1JMTipM3Cd` (devnet, disposable, 0 decimals,
supply 1). Image: `https://gateway.irys.xyz/K5jC35s24VjxakLYjtJvcfEVbSUkqNJx2aC3ihuuvtr`.
Metadata JSON: `https://gateway.irys.xyz/6kdjMGginQG3hbVtGgp2YVyAfaHwRH1d3Em28HsmGSjm`.
The metadata flow (steps 3–5 + the disable calls) was run and verified via direct RPC query on
2026-07-15.

The transfer-fee configuration in step 1 was verified separately on 2026-07-17 on a disposable
devnet mint (`LhghiS2pAdbbCK4hR97sRAnPkvbHWoiXrPdqdeQDDBH`, decimals 9): `create-token` with the
`--transfer-fee-*` flags produced `transferFeeBasisPoints: 150`, `maximumFee: u64::MAX`, and both
fee authorities defaulting to the authority wallet; a 100,000-token transfer withheld exactly 1,500
(1.5%, uncapped).

This procedure is what mainnet deployment should follow — decimals (9), supply (1,000,000,000),
and network flags are the only values that change.
