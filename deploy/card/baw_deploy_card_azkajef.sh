#!/usr/bin/env bash
# PREVIEW ONLY: simulate deploying AgentKudosCard from azkajef through the CREATE2 deployer.
# Nothing is signed or sent. After the user reviews the preview and explicitly confirms:
#   BINANCE_BAW_DIR=/home/box/.baw-azkajef baw contract-call execute --requestId <requestId> --json
# Needs: session CONNECTED, Developer Mode on, ~0.0003 BNB.
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
