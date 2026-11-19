#!/usr/bin/env bash
# Builds calldata for deploying AgentKudos through the canonical CREATE2 deployer
# (0x4e59b44847b379578588920cA78FbF26c0B4956C, present on BSC). Read-only: signs and sends nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH=$HOME/.foundry/bin:$PATH
FACTORY=0x4e59b44847b379578588920cA78FbF26c0B4956C
REGISTRY=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
USDT=0x55d398326f99059fF775485246999027B3197955
USDC=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
RPC=${READ_RPC:-https://bsc-dataseed.bnbchain.org}
forge build --silent
BC=$(forge inspect AgentKudos bytecode)
ARGS=$(cast abi-encode "c(address,address,address)" $REGISTRY $USDT $USDC)
INIT=$BC${ARGS:2}
SALT=$(cast keccak "AgentKudos.v1")
echo "${SALT}${INIT:2}" > deploy/create2_calldata.hex
echo "$ARGS" > deploy/constructor_args.hex
ADDR=$(cast create2 --deployer $FACTORY --salt $SALT --init-code $INIT | awk '{print $1}' | tail -1)
echo "$ADDR" > deploy/predicted_address.txt
echo "predicted AgentKudos address: $ADDR"
echo "estimated gas: $(cast estimate --rpc-url $RPC $FACTORY $(cat deploy/create2_calldata.hex))"
