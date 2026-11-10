# Auto-Allowance Dripper

**Set it once. It pays forever. Nobody has to press anything ever again.**

The Auto-Allowance Dripper is a cross-chain automation built for the
[Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon)
(track: **Set It and Forget It**). It turns a one-time setup into an endless,
self-running allowance: a vault on **Base Sepolia** holds funds, and every
20 minutes — on schedule, without any keeper, bot server, or human click —
a fixed drip of **0.001 ETH** lands in the recipient's wallet.

Think of it as a standing order that no bank can offer: the "scheduler" is a
Reactive Smart Contract living on the **Lasna** testnet, woken by the
protocol's own Cron1000 event. It checks the schedule, and when a drip is due
it orders the vault on the other chain to pay. The whole loop — origin event
→ reactive transaction → cross-chain callback → payout — has already executed
on testnet and is proven by the transaction trail below.

> Everything here runs on testnets with test tokens. No real funds are involved.

## How it works

```
Lasna testnet (5318007)                              Base Sepolia (84532)
───────────────────────                              ────────────────────

Cron1000 event (~every 17 min)
  emitted by 0x0000…fffFfF
        │
        ▼
┌──────────────────────┐   callback via Reactive     ┌──────────────────────┐
│  AllowanceDripper    │ ──────────────────────────▶ │  AllowanceVault      │
│  (Reactive contract) │   system contract + proxy   │  (destination)       │
│                      │                             │                      │
│  · is a drip due?    │                             │  · pays its OWN      │
│  · if yes: request   │                             │    owner-set amount  │
│    callback          │                             │    to the recipient  │
└──────────────────────┘                             └──────────┬───────────┘
                                                              │
                                                              ▼
                                                     recipient wallet
                                                     +0.001 ETH per drip
```

1. **The clock.** The Reactive protocol emits a `Cron1000` event roughly every
   17 minutes. `AllowanceDripper` subscribed to it at deployment — no external
   trigger service is involved.
2. **The brain.** On each tick, the dripper's `react()` runs. If the schedule
   says a drip is due, it asks the Reactive system contract
   (`0x8888888888888888888888888888888888888888`) to deliver a callback to
   Base Sepolia. If nothing is due, it returns immediately and cheaply —
   `react()` never reverts, because a reverting reaction is still billed.
3. **The vault.** The callback arrives at `AllowanceVault` through Base
   Sepolia's callback proxy, authenticated two ways (the caller must be the
   proxy, and the network-injected sender must be our dripper). The vault then
   pays **its own configured amount** to **its own configured recipient** —
   the callback payload's amount is never trusted, so no misbehaving caller
   can ever extract more than one drip per callback.
4. **Repeat.** The schedule advances by 20 minutes and the loop continues,
   unattended, until the vault runs dry or the owner reconfigures it.

## Deployed contracts (verified live, loop running)

Both contracts were deployed by the same account at nonce 0 on each chain, so
they share one address — a coincidence, verified by code and `owner()` on both sides.

| Contract | Chain | Address |
|---|---|---|
| `AllowanceDripper` | Reactive Lasna testnet (5318007) | `0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd` |
| `AllowanceVault` | Base Sepolia (84532) | `0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd` |

- Deployer (testnet-only account): `0xB685c2aDDD6c7cE962AE2495ed8ac2EBe0243288`
- Demo recipient: `0xA51249D6D67dEB0A78a6699367b3624a61d19BC1`
- Live configuration: drip **0.001 ETH** every **1200 s**; vault funded for 10 drips.
- Source verification (Sourcify, **exact match** on both chains):
  [Lasna 5318007](https://repo.sourcify.dev/contracts/full_match/5318007/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd/) ·
  [Base Sepolia 84532](https://repo.sourcify.dev/contracts/full_match/84532/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd/)
- Explorers: [Lasna (Reactscan)](https://lasna.reactscan.net/address/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd) ·
  [Base Sepolia (Blockscout)](https://base-sepolia.blockscout.com/address/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd)

## Proof: the full loop, on-chain

**Funding** (so the two-sided Reactive fee model is covered):

| Step | Tx |
|---|---|
| 0.1 Sepolia ETH → 10.5 lREACT (converter `0x9b9BB25f…Cf434`) | `0x93f179db53e57ffc91e960e0be1db59ce043096f667db750528f58558469dfe1` |
| Bridge 0.05 ETH Sepolia → Base Sepolia (official L1StandardBridge) | `0xb8e94e31b91e571bc862d97607c9141740715d1335112bf0defa326a4e8b729a` |

**Deployment & configuration:**

| Step | Tx |
|---|---|
| Deploy `AllowanceDripper` (Lasna) | `0x1f6ac0b443680d8cfc2ac6529a040151448bd6b858b02fdbedbf9a47f50d2112` |
| Deploy `AllowanceVault` (Base Sepolia) | `0x8a95ccbeddc8d69bbb5f799fe6a2e627d3e22da183a7177341dfe7d6751d6d1a` |
| Credit dripper reserves (5 lREACT) | `0x7a429a251f66bc5edd2f34a67ca746ac13532001ae1085ef70fa21cb19a12599` |
| Credit vault callback reserves (0.01 ETH) | `0xee175d2a2ffb54e4b1df3431f3e7fdf1e2d9603aa05ce55ef1f001424a0824da` |
| Fund vault payout balance (0.01 ETH) | `0x65b16809c9e66eb441d63fe72466e5aff55a6ec16561fb55aecff614bfbb3dbb` |
| `setRecipient` · `setDripAmount` · `setVault` · `setSchedule` | `0x267f89c3…` · `0xac1cb879…` · `0xec7a253c…` · `0x8dbf2d0c…` (full hashes in `NOTES.md`) |

**Drip #1 — one complete reactive loop, verified end to end:**

1. **Origin event:** Cron1000 emitted at Lasna block **7,998,000**.
2. **Reactive tx (Lasna):**
   [`0x21e7baff5d75bd943069cceeb7f374fed2b2154a44c34f3248700296842668d5`](https://lasna.reactscan.net/tx/0x21e7baff5d75bd943069cceeb7f374fed2b2154a44c34f3248700296842668d5)
   — the dripper woke, found a drip due, emitted `DripTriggered(1, …)` and
   requested the callback (≈0.016 lREACT drawn from reserves).
3. **Callback tx (Base Sepolia):**
   [`0x21b4f5af2ad97aebfdb1c9bac8eff511e2ef6a05d1792ebc0f78ea6dcc80d3e0`](https://base-sepolia.blockscout.com/tx/0x21b4f5af2ad97aebfdb1c9bac8eff511e2ef6a05d1792ebc0f78ea6dcc80d3e0)
   — relayer → callback proxy `0x476F44b1…3585` → vault emitted
   `Released(recipient, 0.001 ETH, #1)`.
4. **Effect:** recipient balance went **0 → 0.001 ETH**;
   `releasesTriggered = 1`, `releasesPaid = 1`, outstanding debt **0** on both
   sides — and the schedule advanced, so the next drip fires on its own.

An honest caveat: `SYSTEM.getCallbacks(bytes32)` reverts on the live Lasna
system contract (the selector appears absent in the Omni deployment), so the
two-chain receipt/log trail above — origin block, reactive tx, callback tx,
`Released` event — is the proof of record. Every number in this README was
read back from the chains, not from local state.

## Why this fits the judging criteria

- **Execution** — A real reactive loop ran on real (test) chains: origin
  event, reactive transaction, cross-chain callback, and a state-changing
  payout, all linked by the hashes above. This is not a mock or a simulation.
- **Integration** — The project uses the actual Omni machinery end to end:
  `SYSTEM.subscribe` to a protocol cron event, `SYSTEM.requestCallbackV_1_0`
  for the cross-chain callback, the destination chain's callback proxy with
  `depositTo` reserves, and the two-sided fee model (lREACT on the reactive
  side, native ETH on the destination side) funded and debt-free.
- **Usefulness** — Recurring payouts are a real, everyday need (allowances,
  subscriptions, stipends, vesting-style releases). Today they require a
  keeper bot, a server, or a human remembering to click. Here the schedule
  lives in a contract: configure it once and it simply keeps its promise.
- **Craft** — Two small, heavily commented contracts (~200 lines each) with a
  defensive design: `react()` can never revert, business failures emit events
  instead of reverting, the vault never trusts payload amounts, and both sides
  expose `coverDebt()` escape hatches because unpaid debt silently halts
  Reactive execution. 12 unit tests cover the payout path, authentication,
  scheduling, and pause logic. Sources are Sourcify-verified (exact match).

## Repository layout

```
src/reactive/AllowanceDripper.sol      the reactive brain (Lasna)
src/destination/AllowanceVault.sol     the payout vault (Base Sepolia)
test/                                  12 Foundry tests + a mock callback proxy
demo/index.html                        live, read-only status page (see below)
lib/reactive-lib-omni/                 vendored Reactive Omni library (pinned)
lib/forge-std/                         vendored Foundry standard library
NOTES.md                               full build/deploy journal with every hash
```

## Run the tests

Requires [Foundry](https://book.getfoundry.sh/) (developed with forge/cast 1.9.0, solc 0.8.29).

```shell
forge build
forge test        # 12 passed, 0 failed
```

One testing note: on a local chain the SYSTEM address (`0x8888…8888`) has no
code, and Solidity reverts when calling codeless addresses — so the dripper
tests etch a 1-byte stub at that address and impersonate the system contract
with `vm.prank`, which exercises the real logic faithfully.

## Demo (under 3 minutes)

Open **`demo/index.html`** — a single static page that reads live chain state
in the browser (public RPCs only, no wallet, no keys) and shows, in big
numbers: drips paid, recipient balance, vault balance, and a countdown to the
next scheduled drip.

Script:

1. **(0:00)** Show the demo page: recipient balance and "drips paid" counter
   as they are. Point at the live countdown to the next drip.
2. **(0:30)** On Lasna Reactscan, show the dripper contract and the Cron1000
   subscription — this is the clock that wakes it; no server of ours exists.
3. **(1:00)** Wait for the countdown to hit zero and the next Cron1000 tick:
   a new reactive transaction appears on Lasna (`DripTriggered`).
4. **(1:40)** Seconds later the callback lands on Base Sepolia. Refresh the
   demo page: **drips paid +1, recipient balance +0.001 ETH**, "last drip"
   line updated — and nobody signed anything.
5. **(2:30)** Close on the proof trail in this README and the Sourcify
   exact-match badges. Set it, forget it — it just paid again.

(Tip for filming: call `setSchedule(0.001 ether, 1200, 0)` shortly before
recording so a drip falls inside the take, and top up the vault if many drips
have elapsed since funding.)

## Technical notes (Omni, not legacy Reactive)

This project targets **Reactive Omni** — the current architecture, which
differs from the legacy Reactive Network most online examples still show:

- No RVM, no `vm` modifier, no `Callback` events. Contracts inherit
  `AbstractReactive` / `AbstractCallback` from
  [`reactive-lib-omni`](https://github.com/Reactive-Network/reactive-lib-omni)
  (vendored here at commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`).
- Everything goes through the system contract
  `0x8888888888888888888888888888888888888888` on chain **5318007** (Lasna),
  RPC `https://lasna-rpc.rnk.dev/`.
- The first argument of every callback payload is an `address` placeholder
  passed as `address(0)`; the network overwrites it with the reactive
  contract's address — that is how the vault authenticates callbacks.
- The vault's authorized sender is fixed at construction and **immutable**,
  so deployment order matters: dripper first, then the vault.
- Callbacks are requested with a 1,000,000 gas limit (protocol minimum
  100,000). All scheduling uses timestamps, never block numbers.
- Fees are two-sided: reactions burn lREACT credited via `SYSTEM.depositTo`;
  destination callbacks are billed in the destination chain's native token
  via the callback proxy (`0x476F44b11F5C942c58f4c8E3d0300E5710743585` on
  Base Sepolia). Any outstanding debt silently stops execution — hence the
  `coverDebt()` functions on both contracts.
- Deployment order to reproduce: fund deployer → convert ETH to lREACT →
  bridge ETH to Base Sepolia → deploy dripper → deploy vault → credit both
  reserves → fund vault → configure recipient/amount/schedule → watch it drip.
  `NOTES.md` records the exact transactions from the live run.

## License

The contracts and tests in `src/` and `test/` are released under the
[MIT License](LICENSE). Vendored libraries keep their own terms:
`lib/forge-std` is dual-licensed Apache-2.0/MIT (license files included), and
`lib/reactive-lib-omni` is vendored unmodified from the Reactive Network
GitHub organization at the pinned commit above.
