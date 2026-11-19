# AgentKudos

Tip any `.ai` Agent ID on BNB Smart Chain. Send BNB, USDT or USDC to `name.ai`; the contract resolves the name on-chain through the SPACE ID Agent ID registry and forwards the funds to the Agent ID owner in the same transaction. Every tip, its message and the sender's own Agent ID are recorded on-chain and power two leaderboards (most kudos received, most generous Agent ID tippers).

## Deployment (BSC mainnet)
- **AgentKudos:** [`0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921`](https://bscscan.com/address/0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921#code)
- **Deploy tx:** [`0x8c5bd1e586a50e7f1574fda4a68c3bf7bd5adda2ebc3ba7532c074686b13b061`](https://bscscan.com/tx/0x8c5bd1e586a50e7f1574fda4a68c3bf7bd5adda2ebc3ba7532c074686b13b061) (block 134458942, via the CREATE2 deployer `0x4e59…956C`, salt `keccak256("AgentKudos.v1")`)
- **Source verified:** [Sourcify exact match](https://repo.sourcify.dev/56/0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921)
- Constructor: registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`, USDT `0x55d398326f99059fF775485246999027B3197955`, USDC `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`

Live site: https://skytrasha.github.io/agentkudos/ · Built for the Agent ID Hackathon (submission 2026-11-18 → 2026-12-09 08:00 UTC).

## How Agent ID is used
- **No sign-up:** every registered `.ai` name can receive tips immediately. Owners can optionally set a public bio (`setBio`, requires `registry.handleOf(msg.sender)`).
- **Payments by name:** `tip("alice", msg)` resolves `registry.ownerOfHandle("alice")` at tip time and pays that address. No address book, no copy-pasting hex addresses.
- **Reputation:** each `Tipped` event carries the sender's own handle; on-chain counters give per-name totals, per-tipper totals and distinct recipients.
- **Agent-native:** `web/agent-skill.md` lets Agentic Wallet agents tip via `baw contract-call preview/execute` with user confirmation on every transaction.

## Agent ID registry (verified)
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` — contract `HandleRegistry`, "SPACE ID Agent ID" (AI), ERC-721, soulbound, Sourcify exact match. Handles are stored **without** `.ai`, 3–20 chars `[a-z0-9]`, `tokenId = uint256(keccak256(handle))`.
- `balanceOf(address)` > 0 ⇒ holds an Agent ID
- `handleOf(address) → string` (selector `0xc50a1514`)
- `ownerOfHandle(string) → address` (selector `0x1da94fb4`, returns 0x0 if unregistered)

## Contract: `src/AgentKudos.sol`
| Function | Who | Effect |
|---|---|---|
| `setBio(bio)` | Agent ID owner | optional public bio (not needed to receive) |
| `tip(handle, message)` payable | anyone | forwards `msg.value` to the name owner |
| `tipToken(handle, token, amount, message)` | anyone | `transferFrom(sender → name owner, amount)`; USDT/USDC only |
| `profileOf`, `getRecipients`, `getTippers`, `received`, `sent`, … | view | tip page + leaderboards from storage; `profileOf` never returns an address |

Constructor (immutable): registry `0x60B9…022F`, USDT `0x55d3…7955`, USDC `0x8AC7…580d`.

### Owner permissions: none
- No owner, admin, `Ownable`, proxy, pause, fee, mint, blacklist, or upgrade function.
- No function can withdraw or move user funds. The contract has no `receive`/`fallback`, and funds are never held: native tips are forwarded in the same call, and tokens go directly from the tipper to the recipient.
- Token approvals: the UI and agent skill request **exactly** the tip amount; the contract only pulls `amount`.
- Reentrancy: `nonReentrant` on both tip paths, state updated before external calls.
- Dependency note: the SPACE ID registry has its own owner (it can register handles via `adminRegister` and set its signer); it cannot transfer existing handles (soulbound). Tips always go to `ownerOfHandle` at tip time; unregistered names revert with `UnknownHandle`.

## Safety red lines (hackathon rules)
| Rule | How AgentKudos complies |
|---|---|
| No web QR / pairing-code login | Frontend only uses the injected browser wallet (`window.ethereum`). No QR, no pairing code. |
| No stored sessions | Fully static site, no backend, nothing stored server-side. |
| No confirmation bypass | Every tx is signed in the user's wallet; agent skill mandates preview → explicit confirm → execute for each tx. |
| No unauthorised transfers | No scheduled/automatic transfers, no bundled extra transfers, exact-amount approvals only. |
| Open source + disclosed owner perms | MIT, verified on BscScan, no owner permissions (above). |
| No brand impersonation | Name "AgentKudos"; no "Binance"/"BNB" in name or domain. Footer states it is independent. |
| No credential collection | Never asks for seeds, keys, API secrets or pairing codes. |
| No promised returns | Tips are gifts; UI says nothing offers returns. |
| Not a "look up wallets by name" tool | Purpose is paying a name, not revealing it: the UI and `profileOf` never display or return a recipient's address, and the agent skill forbids reporting it. |

## Develop
```bash
forge test --no-match-contract Fork                         # unit + fuzz
BSC_RPC_URL=https://bsc-dataseed.bnbchain.org forge test --match-contract Fork   # mainnet fork, real registry
./deploy/make_create2.sh                                     # CREATE2 calldata + predicted address (read-only)
cd web && python3 -m http.server 8080                        # frontend
```

## Deploy
Deterministic via the canonical CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` with salt `keccak256("AgentKudos.v1")`, so it can be deployed either by an Agentic Wallet (`baw contract-call` to the deployer with `deploy/create2_calldata.hex`) or by any EOA (`script/Deploy.s.sol`). Predicted address: see `deploy/predicted_address.txt` (changes if the bytecode changes).

Agentic Wallet deploy (preview only, then execute after explicit confirmation): `deploy/baw_deploy_azkajef.sh`. Requires Developer Mode on in the Binance App.
