# On-chain token metadata — mainnet procedure

Status: verified end-to-end on devnet (2026-07-15), rehearsal mint `6Y2EHSvhZyzJE6wESZcAKtKzKX37Ex3DgY1JMTipM3Cd`. Not yet run on mainnet.

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

## Verified procedure (7 steps, 4 disable calls)

Order matters: `initialize-metadata` must sign with the mint authority, so it has to run before
mint authority is revoked (step 6). Freeze authority (step 7) can be revoked any time after minting.

```bash
AUTH=<mainnet-authority-keypair>
MINT_KP=<mainnet-mint-keypair>

# 1. Create mint with Metadata Pointer + Token Metadata extension, and freeze enabled
spl-token create-token --enable-metadata --enable-freeze \
  -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb \
  --decimals 9 -u mainnet-beta \
  --mint-authority $(solana-keygen pubkey $AUTH) \
  --fee-payer $AUTH \
  $MINT_KP

MINT=$(solana-keygen pubkey $MINT_KP)

# 2. Mint the full supply
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

Query the mint directly and confirm all four authority fields are `null`, plus the correct
name/symbol/uri:

```bash
curl -s <mainnet RPC> -X POST -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0","id":1,"method":"getAccountInfo",
  "params":["'"$MINT"'", {"encoding":"jsonParsed"}]
}'
```

Expect: `mintAuthority: null`, `freezeAuthority: null`,
`metadataPointer.state.authority: null`, `tokenMetadata.state.updateAuthority: null`,
`tokenMetadata.state.name/symbol/uri` matching what was set in step 3.

## Devnet rehearsal reference

Mint: `6Y2EHSvhZyzJE6wESZcAKtKzKX37Ex3DgY1JMTipM3Cd` (devnet, disposable, 0 decimals, supply 1).
Image: `https://gateway.irys.xyz/K5jC35s24VjxakLYjtJvcfEVbSUkqNJx2aC3ihuuvtr`.
Metadata JSON: `https://gateway.irys.xyz/6kdjMGginQG3hbVtGgp2YVyAfaHwRH1d3Em28HsmGSjm`.
All 7 steps run and verified via direct RPC query on 2026-07-15. This procedure is what mainnet
deployment should follow — decimals (9), supply (1,000,000,000), and network flags are the only
values that change.
