# Security Policy

Ash & Ember ($ASHEM) does not pay for a security audit. Instead, the code is public, every on-chain action is traceable, and we run a **public bug bounty**: we pay for real problems found, not for a stamp of approval. This is payment for security work — in the spirit of "don't trust, verify."

This policy covers the `-ASHEM` repository: the core mechanism that moves real funds on mainnet.

## Scope

In scope — the logic that moves real funds:
- **Harvest / endgame** — fee harvesting, the burn/dev split, and the endgame state machine.
- **Circuit breaker** and **dynamic buffer** — the guarantees that protect the 300,000,000 floor.
- Fee calculation and harvest accounting.
- Anything that could forge, skip, or break a step of the authority revocation.

Out of scope (open a normal GitHub Issue instead — not a bounty report):
- Typos, style suggestions, cosmetic bugs.
- Findings that are not exploitable (no PoC / no funds at risk).

## How to report

- **Exploitable findings → private report** via GitHub's **"Report a vulnerability"** button (Security tab → Advisories). Do **not** open a public Issue for an exploitable bug — that would expose an unpatched hole while others could use it.
- **Non-exploitable / cosmetic findings → a normal public Issue.**

Include enough to reproduce: a clear description, the affected component, and a proof-of-concept where possible.

## Response times

Two clocks. We commit to acknowledging fast; fix timelines are honest targets, not hard promises — this is a small project, not a team with a 24/7 security rotation.

| Severity | First acknowledgment | Severity confirmation | Fix (target) |
|---|---|---|---|
| Critical | ≤ 72h | ≤ 7 days | as fast as possible |
| High | ≤ 72h | ≤ 7 days | ≤ 30 days |
| Medium / Low | ≤ 7 days | — | no hard deadline |

We acknowledge every report within 72h regardless of severity — even when we can't investigate immediately.

## Severity & bounty

Bounties are **denominated in SOL** (not $ASHEM — paying in the token would look like disguised distribution, which this project has explicitly ruled out).

The model is a **hybrid**: a modest fixed floor, **or** a percentage of the funds a report demonstrably puts at risk (with PoC) — **whichever is greater**. Industry averages are calibrated against protocols holding millions; they don't transfer to a project with ~$50–90 of real liquidity, and promising those numbers would be a promise we couldn't back.

| Severity | Example | Fixed floor (now) | % of funds at risk (scales with the project) |
|---|---|---|---|
| **Critical** | Evade the circuit breaker; drain the vault beyond its cap; forge or skip a revocation step; break the endgame state machine | ~0.2 SOL | up to 10% of funds demonstrably at risk (vault + LP) — whichever is greater |
| **High** | Break the floor guarantee (dynamic buffer); force an incorrect fee calculation | ~0.1 SOL | proportional, below Critical |
| **Medium** | Harvest errors; accounting drift; rate-limit failures | ~0.03–0.05 SOL | proportional |
| **Low** | Minor, non-exploitable findings | Public acknowledgment | — |

## How payments work

- The **bounty pool is bounded and declared**: currently **0.5 SOL** (topped up as needed) — never an open-ended promise.
- Bounties are paid from a **dedicated bounty wallet**, separate from the dev, authority, and dispenser wallets (one role per wallet).
- The "% of funds at risk" is **only the formula for how much we pay — never the source of the money**. Payments never come from the locked/burned LP or from the fee vault; the bounty wallet is funded separately.
- Confirmed reports and payments are recorded in a **public ledger** in this repo (date, severity, amount, reporter wallet, fix commit) — verifiable, like our harvest ledger.

## Disclosure

Please give us a reasonable window to confirm and fix before any public disclosure of an exploitable finding. We'll credit you in the public ledger unless you prefer to remain anonymous.