#!/usr/bin/env bash
# PREVIEW ONLY: builds AgentKudos tip(handle,message) calldata and runs `baw contract-call preview`.
# It never runs `execute`; nothing is signed or broadcast. Execute manually only after the user
# has reviewed the preview and explicitly confirmed:
#   BINANCE_BAW_DIR=<BAW_DIR> baw contract-call execute --requestId <requestId> --json
# Usage: deploy/tip_preview.sh <BAW_DIR> <fromAddress> <handle> <message> <valueWei>
#   e.g. deploy/tip_preview.sh /home/box/.baw-azkajef 0xB758bE9BD9178ccB4F51cCbFCc89A49e76E7AF55 kazekage "gm from AgentKudos" 100000000000000
set -euo pipefail
[ $# -eq 5 ] || { echo "usage: $0 <BAW_DIR> <from> <handle> <message> <valueWei>" >&2; exit 1; }
BAW_DIR=$1; FROM=$2; HANDLE=$(echo "${3%.ai}" | tr 'A-Z' 'a-z'); MSG=$4; VALUE=$5
KUDOS=0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921
REGISTRY=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
RPC=${READ_RPC:-https://bsc-dataseed.bnbchain.org}
export PATH=$HOME/.foundry/bin:$PATH
[[ $HANDLE =~ ^[a-z0-9]{3,20}$ ]] || { echo "invalid handle: $HANDLE" >&2; exit 1; }
[[ $VALUE =~ ^[0-9]+$ && $VALUE -gt 0 ]] || { echo "valueWei must be a positive integer" >&2; exit 1; }
[ "$(printf %s "$MSG" | wc -c)" -le 280 ] || { echo "message > 280 bytes" >&2; exit 1; }
REG=$(cast call --rpc-url "$RPC" $KUDOS "profileOf(string)(bool,uint32,string)" "$HANDLE" | head -1)
[ "$REG" = "true" ] || { echo "$HANDLE.ai is not a registered Agent ID" >&2; exit 1; }
FROM_HANDLE=$(cast call --rpc-url "$RPC" $REGISTRY "handleOf(address)(string)" "$FROM")
[ "$FROM_HANDLE" != "\"$HANDLE\"" ] || { echo "cannot tip yourself" >&2; exit 1; }
DATA=$(cast calldata "tip(string,string)" "$HANDLE" "$MSG")
echo "Preview: tip $HANDLE.ai $(cast from-wei $VALUE) BNB from $FROM ($FROM_HANDLE), message: $MSG" >&2
echo "calldata: $DATA" >&2
BINANCE_BAW_DIR="$BAW_DIR" baw contract-call preview --binanceChainId 56 --from "$FROM" --to $KUDOS --value "$VALUE" --inputData "$DATA" --json
