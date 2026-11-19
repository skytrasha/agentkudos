#!/usr/bin/env bash
# Deploy AgentKudos from the azkajef Agentic Wallet through the canonical CREATE2 deployer.
# Step 1 (this script) only PREVIEWS: it simulates and returns a requestId; nothing is signed or sent.
# Prerequisites: session CONNECTED, Developer Mode enabled in the Binance App, ~0.0002 BNB for gas.
# Step 2, only after the user has reviewed the preview and explicitly confirmed:
#   BINANCE_BAW_DIR=/home/box/.baw-azkajef baw contract-call execute --requestId <requestId> --json
set -euo pipefail
cd "$(dirname "$0")"
export BINANCE_BAW_DIR=/home/box/.baw-azkajef
baw contract-call preview \
  --binanceChainId 56 \
  --from 0xB758bE9BD9178ccB4F51cCbFCc89A49e76E7AF55 \
  --to 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --value 0 \
  --inputData "$(cat create2_calldata.hex)" \
  --json
