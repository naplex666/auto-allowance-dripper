# Auto-Allowance Dripper — Build Notes

Reactive Omni Buildathon · track "Set It and Forget It" · deadline 5 Dec 2026 20:00 UTC.
Authoritative design/API source: `../hidden_files/research-brief.md` (Omni pattern, NOT legacy Reactive).

## Phase 1 status (9 Nov 2026): setup + contracts compiling ✅

- `forge build` passes (solc 0.8.29; only non-blocking lint suggestions remain).
- `forge test`: **12/12 pass** (6 vault + 6 dripper).

## Toolchain

- forge + cast **1.9.0** at `~/.local/bin/` (already installed; no install needed).

## Dependencies (vendored under `lib/`, pinned)

| Lib | Source | Pin |
|---|---|---|
| reactive-lib-omni | https://github.com/Reactive-Network/reactive-lib-omni (plain clone into `lib/reactive-lib-omni`) | commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8` (2026-05-21) |
| forge-std | installed by `forge init` | package version 1.17.0 |

No OpenZeppelin: the Omni library is self-contained and the brief's patterns
don't require OZ; ownership is a minimal hand-rolled `onlyOwner` in each
contract (less surface, easier for judges to read).

Remappings (`foundry.toml`): `@reactive/` → `lib/reactive-lib-omni/src/`, `forge-std/` → `lib/forge-std/src/`.

## Contracts

| Contract | File | Chain (deploy phase) | Role |
|---|---|---|---|
| `AllowanceDripper` | `src/reactive/AllowanceDripper.sol` | Lasna testnet 5318007 | Reactive brain. Subscribes to Cron1000 (topic0 `0xe20b…e3f4`, emitter `0x0000…fffFfF`, chainId = own chain) in its constructor. Holds schedule (`dripAmount`, `interval`, `nextRelease` — timestamps only), `vault` address, soft `paused` flag. `react()` (onlySystem) never reverts: filters defensively, returns cheaply when not due, wraps `SYSTEM.requestCallbackV_1_0` in try/catch, advances `nextRelease` from *now* only on success. Callback payload `release(address,uint256)` with `address(0)` placeholder first arg; gas limit 1,000,000 (protocol min 100k). Owner: `setVault`, `setSchedule(amount, interval, firstIn)`, `setPaused`, `pauseCron`/`resumeCron` (real unsubscribe/subscribe via one centralized helper each — exact six-arg match), `coverDebt()`, `withdraw`, `transferOwnership`. |
| `AllowanceVault` | `src/destination/AllowanceVault.sol` | Base Sepolia 84532 | Destination wallet. Extends `AbstractCallback`; constructor `(IPayable callbackProxy, address callbackSender)` — sender is IMMUTABLE, so deploy the dripper first. `release(reactive_, requestedAmount_)` guarded by `onlyServiceProvider` + `onlyCallbackSender`. The vault is authoritative about money: it pays its own owner-set `dripAmount` to its owner-set `recipient`; the payload amount is ignored for value. Business failures (paused / no recipient / zero amount / low balance / recipient rejects) emit events and return — never revert. Owner: `setRecipient`, `setDripAmount`, `setPaused`, `coverDebt()`, `withdraw`, `transferOwnership`. |

Tests: `test/AllowanceVault.t.sol`, `test/AllowanceDripper.t.sol`, `test/MockCallbackProxy.sol`.
Note for future test work: locally the SYSTEM address (0x8888…8888) has no code and Solidity
reverts calls to codeless addresses — the dripper test etches a 1-byte stub (`vm.etch(SYSTEM, hex"00")`)
and impersonates SYSTEM with `vm.prank`, which faithfully exercises our logic.

## Testnet wallet

- Address: **`0xB685c2aDDD6c7cE962AE2495ed8ac2EBe0243288`** (fresh, generated locally with `cast wallet new`; derivation re-verified against the stored key).
- Private key: ONLY in `../hidden_files/testnet-wallet.key` (chmod 600). Never commit it, never print it.
  (Lesson applied: `cast wallet new` on this build prints `address privatekey` on one line when stdout is piped — capture to a file first, parse fields, never echo raw output.)
- Testnet-only, disposable. NOT one of Hasan's real wallets. Same address serves Lasna, Base Sepolia, Eth Sepolia.

## Funding status at phase 1 (9 Nov, historical — superseded by Phase 2 section below)

| Chain | Balance | RPC check |
|---|---|---|
| Lasna 5318007 | 0 lREACT | `https://lasna-rpc.rnk.dev/` live, chain-id verified |
| Base Sepolia 84532 | 0 ETH | `https://sepolia.base.org` live, chain-id verified |
| Eth Sepolia 11155111 | 0 ETH | publicnode RPC OK |

On-chain counterparts verified to have code: Lasna SYSTEM `0x8888…8888`, Base Sepolia callback
proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`, ETH→lREACT converters on Eth Sepolia
(`0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`) and Base Sepolia (`0x2afaFD298b23b62760711756088F75B7409f5967`).

### Funding routes (from the brief) — and the blocker

1. **Test ETH first** (needed for deploys AND to buy lREACT). The well-known faucets
   (Alchemy, QuickNode, Coinbase CDP, Google Cloud) all require an **account login and/or
   captcha in a browser — a human step**. Per instructions: no captcha bypass was attempted.
   A permissionless alternative is the pk910 proof-of-work Sepolia faucet (no account, no
   captcha, scriptable protocol) — not run in this phase (long mining session on this VM);
   evaluate at deploy phase.
2. **lREACT**: no drip faucet. Convert test ETH at 1 ETH → 100 lREACT via the converter
   contracts above (call `request(address)` with value, or plain-send; docs example
   0.1 ETH → 10 lREACT; max 500 lREACT/tx). Needs step 1 done first.

## Phase 2 status (10 Nov 2026): DEPLOYED + LOOP VERIFIED END-TO-END ✅

### Funding (all testnet)
- Sepolia ETH arrived via the pk910 PoW faucet (Hasan mined it on his phone): **0.3725 SepETH**
  paid by faucet wallet `0x6Cc9397c3B38739daCbfaA68EaD5F5D77Ba5F455`.
- **lREACT conversion:** sent 0.1 SepETH to the Eth Sepolia converter
  `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` via `request(address)` →
  tx `0x93f179db53e57ffc91e960e0be1db59ce043096f667db750528f58558469dfe1` (status 1).
  Result: **10.5 lREACT** on Lasna (expected 10; +0.5 extra observed, source unclear — harmless).
- **Bridge Sepolia → Base Sepolia:** official L1StandardBridge (Sepolia)
  `0xfd0Bf71F60660E2f608ed56e1659C450eB113120`, `depositETH(200000, 0x)` with 0.05 ETH →
  L1 tx `0xb8e94e31b91e571bc862d97607c9141740715d1335112bf0defa326a4e8b729a` (status 1;
  OptimismPortal `TransactionDeposited` verified in receipt). L2 relay landed after ~23 min:
  **0.05 ETH** on Base Sepolia. Address verified against docs.base.org base-contracts page
  (beware the widely-circulated wrong variant ending `...311362` — no code; ours ends `...311320`).

### Deployed contracts
| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| `AllowanceDripper` | Lasna 5318007 | `0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd` | `0x1f6ac0b443680d8cfc2ac6529a040151448bd6b858b02fdbedbf9a47f50d2112` |
| `AllowanceVault` | Base Sepolia 84532 | `0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd` | `0x8a95ccbeddc8d69bbb5f799fe6a2e627d3e22da183a7177341dfe7d6751d6d1a` |

(Same address on both chains — same deployer, nonce 0 on each chain. A coincidence, verified
by code + owner() on both sides.) Dripper seeded with 3 lREACT at deploy (payable constructor).
Demo recipient (fresh local wallet, key in `../hidden_files/recipient-wallet.key`, chmod 600):
`0xA51249D6D67dEB0A78a6699367b3624a61d19BC1`.

### Reserves credited
- Lasna: `SYSTEM.depositTo(dripper)` 5 lREACT → tx `0x7a429a251f66bc5edd2f34a67ca746ac13532001ae1085ef70fa21cb19a12599`.
- Base Sepolia: `proxy.depositTo(vault)` 0.01 ETH → tx `0xee175d2a2ffb54e4b1df3431f3e7fdf1e2d9603aa05ce55ef1f001424a0824da`.
  Vault payout capital: plain transfer 0.01 ETH → tx `0x65b16809c9e66eb441d63fe72466e5aff55a6ec16561fb55aecff614bfbb3dbb`.

### Configuration (all status 1)
- Vault `setRecipient(0xA512…9BC1)` → `0x267f89c3453103f181aede4e5513239f2999937e5cb89464b70c6a7caa7b5029`
- Vault `setDripAmount(0.001 ETH)` → `0xac1cb879d7010d7c524ed2da6379c64d5c8cd2791617c55fd9c4d2a5cab5e028`
- Dripper `setVault(vault)` → `0xec7a253ca97f48cf84f1ecf077e22bb691c14eb24982e5781fa9d793f30fe246`
- Dripper `setSchedule(0.001 ETH, 1200 s, firstIn 0)` → `0x8dbf2d0c220ccd7e267bb4342099548a87aee382d2d6f8a3593c9be60fe4cfe1`

### First full loop — PROOF (drip #1)
1. **Origin event:** Cron1000 emitted by `0x0000…fffFfF` at Lasna block **7,998,000**.
2. **Reactive tx (Lasna):** `0x21e7baff5d75bd943069cceeb7f374fed2b2154a44c34f3248700296842668d5`
   (block 7,998,001, status 1, gasUsed 110,860) — SYSTEM log + dripper's `DripTriggered(1, …)`.
   Charge drawn from reserves: ≈0.01615 lREACT.
3. **Callback tx (Base Sepolia):** `0x21b4f5af2ad97aebfdb1c9bac8eff511e2ef6a05d1792ebc0f78ea6dcc80d3e0`
   (block 56,938,501, status 1) — relayer → callback proxy `0x476F…3585` → vault emitted
   `Released(recipient, 0.001 ETH, #1)`. Proxy charge: ≈0.00000099 ETH from vault reserves.
4. **Effect:** recipient balance 0 → **0.001 ETH**; `releasesTriggered = 1`, `releasesPaid = 1`;
   `nextRelease` advanced (+1200 s). Debt = 0 on BOTH sides after the loop.
- Note: `SYSTEM.getCallbacks(bytes32)` **reverts** on the live Lasna system contract (selector
  appears absent in the Omni deployment) — the two-chain receipt/log trail above is the proof
  of record instead. Lasna Reactscan's `/api/v2` also 404s for contract/tx-list endpoints;
  RPC `cast logs`/`cast receipt` worked throughout. Base Sepolia public RPC caps
  `eth_getLogs` to a 200-block range — use Blockscout for history there.

### Balances after drip #1
| Where | Amount |
|---|---|
| Deployer — Sepolia | 0.2222 ETH (reserve) |
| Deployer — Lasna | 2.3216 lREACT |
| Deployer — Base Sepolia | 0.02999 ETH |
| Dripper — balance / SYSTEM reserves | 3 lREACT / 4.9839 lREACT |
| Vault — payout balance / proxy reserves | 0.009 ETH (9 drips left) / 0.009999 ETH |
| Recipient | 0.001 ETH |

The loop keeps running unattended: Cron1000 tick (~17 min) + 1200 s interval ⇒ roughly one
drip per ~2 ticks. Top up the vault's payout balance before the filmed demo if many drips
have elapsed.

## Phase 3 status (10 Nov 2026): PACKAGING ✅ (GitHub push pending one human click)

### Source verification — DONE, exact match on both chains (Sourcify)
- `AllowanceDripper` (Lasna 5318007): **exact_match**, Sourcify matchId **59008091** —
  https://repo.sourcify.dev/contracts/full_match/5318007/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd/
  (verify job `aacc884f-e580-4918-bbdb-fba20b4bce8d`).
- `AllowanceVault` (Base Sepolia 84532): **exact_match**, matchId **59008108** —
  https://repo.sourcify.dev/contracts/full_match/84532/0xf47827d1201e07F0FeB2c6bad7F499a86668f9bd/
  (verify job `64bbf8d4-c406-4aa6-b4f0-fa86f1419434`; constructor args =
  proxy `0x476F…3585` + dripper address). Sourcify's chain registry supports both chains.

### README + license — DONE
- `README.md` rewritten for the repo: pitch, architecture diagram, deployed addresses,
  the full proof trail (funding → deploys → config → drip #1 with explorer links), a
  judging-criteria mapping (Execution/Integration/Usefulness/Craft), test instructions,
  the <3-minute demo script, and the Omni technical notes incl. the honest
  `getCallbacks` caveat. `LICENSE` (MIT) added; `.gitignore` covers `out/`, `cache/`,
  `broadcast/`, `.env`, `*.key`.

### Demo page — DONE and tested live
- `demo/index.html`: single static page, **read-only** (plain JSON-RPC `eth_call` /
  `eth_getBalance` + Blockscout API; no wallet, no signing anywhere). Shows recipient
  balance, drips paid, vault balance + drips left, drips triggered, dripper lREACT,
  a per-second countdown to `nextRelease`, and a "Last drip: 0.001 ETH sent
  automatically at …" line resolved from the newest `Released` event (topic
  `0x82e416ba…e8dd`) via Blockscout, linked to the callback tx.
- Every selector was verified against the live contracts with cast first
  (`releasesPaid 0x084267be`, `releasesTriggered 0x1e4f8272`, `nextRelease 0xa1571902`,
  `dripAmount 0x35a1529b`, `recipient 0x66d003ac`, `paused 0x5c975abb`); both RPCs and
  Blockscout return CORS headers a browser accepts. Tested by serving the page
  (HTTP 200), `node --check` on the inline script, and a Node smoke test replaying
  the page's exact calls — it rendered the true live state (paid 1, recipient
  0.001 ETH, vault 0.009 ETH / 9 drips left, next drip ~10 min out, last-drip line
  pointing at callback tx `0x21b4f5af…d3e0`, 2026-11-10 11:19:29 UTC).

### GitHub repo — prepared locally; creation via connector BLOCKED (403)
- `create_repository` through the GitHub connector failed:
  `403 Resource not accessible by integration` — the Muse GitHub App cannot create
  repositories in the account. (Repo confirmed absent first: API 404.) Per connector
  rules no alternate auth (gh/PAT) was attempted.
- **Unblock (one human click):** Hasan creates an empty PUBLIC repo named
  `auto-allowance-dripper` under `naplex666` in the GitHub UI (no README/gitignore
  init), and makes sure the Muse GitHub App installation can access it. The push
  is then a single connector `push-files` snapshot.
- Local preparation is complete: `project/` is now a clean git repo (branch `main`,
  commit `9144e1c8be698763b471dd51ef1fbc3f16689962`) tracking exactly the intended
  59-file / ~1.0 MiB selection: root docs + `foundry.toml` + `.gitignore`,
  `src/` (2 contracts), `test/` (3 files), `demo/index.html`, forge-std `src/` +
  its two license files + package.json/README/foundry.toml, reactive-lib-omni
  `src/` + README/foundry.toml/foundry.lock. A NUL-delimited snapshot manifest of
  the same selection is regenerable from `git ls-files`.
- Deliberately EXCLUDED from the repo: `../hidden_files/` entirely (both wallet
  keys, research brief) — keys never enter the project tree; `out/`, `cache/`
  (build artifacts); forge-std's own `test/`, `.github/`, `scripts/` (dependency
  internals not needed to build); reactive-lib-omni's `.git`, `.gitignore`,
  `.gitmodules` (its clone metadata was moved aside to
  `../hidden_files/reactive-lib-omni-dotgit-backup` so the lib tracks as plain
  files; the vendored sources are byte-identical to the pinned commit).
  Secret scan of the selection: the only 64-hex strings are event topics and
  documented tx hashes — no key material.

## Remaining work
1. ~~Verify sources (Sourcify)~~ — done in Phase 3 (exact match, both chains).
2. ~~Write the public README~~ — done in Phase 3. **GitHub repo push still pending:**
   Hasan creates the empty public repo `naplex666/auto-allowance-dripper` (see the
   Phase 3 blocker above), then push the prepared snapshot.
3. Prepare the <3 min demo script/flow for Hasan — script is in `README.md`, the
   live page is `demo/index.html` (schedule a fresh drip close to filming:
   `setSchedule(…, firstIn 0)` then wait for the next tick; top up the vault if
   its 9 remaining drips have elapsed).
4. Submit on DoraHacks (Hasan's account @zec3on) before 5 Dec 2026 20:00 UTC: repo link,
   both contract addresses, proof tx hashes from "First full loop" above, demo video link.
