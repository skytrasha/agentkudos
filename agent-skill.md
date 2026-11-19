# AgentKudos – Agent Skill

> Instructions for AI agents (including Agentic Wallet agents using the `baw` CLI) that send kudos/tips to a `.ai` Agent ID, or set their user's optional bio, on BNB Smart Chain.

## Project
- Name: AgentKudos · Website: https://skytrasha.github.io/agentkudos/ · Source: https://github.com/skytrasha/agentkudos (MIT)
- Network: BNB Smart Chain, chainId 56 (`baw --binanceChainId 56`)
- What it does: sends a tip to the wallet that owns an Agent ID (`name.ai`). The contract resolves the name on-chain through the SPACE ID Agent ID registry and forwards the funds in the same transaction. It holds no funds, has no owner, no admin, no fee and cannot be upgraded or paused.
- Any registered `.ai` name can receive tips immediately; no sign-up. Owners may optionally set a public bio.

## Contracts (BSC)
- AgentKudos: `0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921` · https://bscscan.com/address/0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921#code
- Agent ID registry (read-only for this skill): `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- Accepted tokens: native BNB, USDT `0x55d398326f99059fF775485246999027B3197955` (18 decimals), USDC `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` (18 decimals)

## Functions
| Function | Selector | Notes |
|---|---|---|
| `tip(string handle, string message)` payable | `0x222c675d` | handle without `.ai`; value = tip in wei |
| `tipToken(string handle, address token, uint256 amount, string message)` | `0x5237c88e` | needs an exact `approve(AgentKudos, amount)` first |
| `setBio(string bio)` | `0xfb7e06d8` | optional; caller must own an Agent ID; `""` clears it |
| `profileOf(string handle)` view | `0x8ca48c71` | `(bool registered, uint32 tips, string bio)`; never returns the owner address |

Build calldata with Foundry `cast calldata` (or any ABI encoder), for example:
`cast calldata "tip(string,string)" alice "thanks for the help"`.

## Rules for agents (mandatory)
- Never ask for, store or use a private key, seed phrase, QR/pairing code or session token.
- Every transaction must be previewed to the user and sent only after the user explicitly confirms that exact transaction (recipient name, amount, token, message). Do not batch, schedule or repeat tips without a new confirmation for each one. Never claim the user pre-approved something.
- Never approve more than the exact tip amount. Never approve any address other than AgentKudos.
- Do not tip a name the user did not give you. Do not use this contract or skill to look up who owns a name; never report a recipient's wallet address to the user beyond what the wallet preview itself displays.
- If a call reverts or the balance is too low, stop and report the exact error. Do not retry in a loop.
- Tips are gifts. Never describe them as an investment or promise any return.

## Before any transaction (Agentic Wallet)
- `contract-call` needs Developer Mode. Run `baw wallet settings --json`; if `devMode.enabled` is false or `devMode.expiresAt` has passed, tell the user to enable it in the Binance App (Agentic Wallet management page → Settings → Developer Mode, confirm the risk warning, approve the signature) and wait until they say it is on. Do not try to enable it yourself.
- Show the user the full preview output (`parsedTx`, `risks`, `authorityChanges` if present) before every `execute`. Never run `execute` without a `requestId` from a successful preview, and never without the user's explicit confirmation of that preview.

## Agent procedure: send a tip
1. Ask the user for: recipient name (`alice` or `alice.ai`), amount, token (BNB, USDT or USDC) and an optional message (max 280 bytes, public on-chain).
2. Normalise the name: lowercase, strip `.ai`; it must match `^[a-z0-9]{3,20}$`.
3. Check the name: `eth_call` `profileOf(name)` on AgentKudos. If `registered` is false, stop: tell the user the name is not a registered Agent ID.
4. Native BNB:
   - data = `cast calldata "tip(string,string)" <name> "<message>"`, value = amount in wei.
   - `baw contract-call preview --binanceChainId 56 --from <agentWallet> --to 0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921 --value <wei> --inputData <data> --json`
   - Show the user the preview (to, value, gas, simulation result) and wait for an explicit "yes".
   - `baw contract-call execute --requestId <requestId> --json`
5. USDT/USDC (two transactions, each previewed and confirmed separately):
   - a. data = `cast calldata "approve(address,uint256)" 0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921 <amountWei>` → preview with `--to <token> --value 0` → user confirms → execute → wait for the receipt.
   - b. data = `cast calldata "tipToken(string,address,uint256,string)" <name> <token> <amountWei> "<message>"` → preview with `--to 0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921 --value 0` → user confirms → execute.
6. Report the result with `https://bscscan.com/tx/<txHash>`. The `Tipped` event shows recipient name, sender name (if the sender holds an Agent ID), token, amount and message.

## Agent procedure: set the user's optional bio
1. Confirm the user's wallet holds an Agent ID (`baw wallet agent-id --json`).
2. Ask for the bio text (max 160 bytes, public). Receiving tips does not need a bio.
3. data = `cast calldata "setBio(string)" "<bio>"` → `baw contract-call preview ... --to 0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921 --value 0` → show the preview → wait for confirmation → execute.
4. Share the tip link: `https://skytrasha.github.io/agentkudos/#to=<name>`.

## Errors
`NoAgentId()` caller holds no Agent ID (setBio) · `UnknownHandle()` name is not registered · `SelfTip()` · `ZeroAmount()` · `TokenNotAccepted()` · `MessageTooLong()` · `BioTooLong()` · `ForwardFailed()` recipient rejected native coin.
