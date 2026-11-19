#!/usr/bin/env bash
# Builds CREATE2 calldata for AgentKudosCard via 0x4e59b44847b379578588920cA78FbF26c0B4956C. Read-only.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH=$HOME/.foundry/bin:$PATH
FACTORY=0x4e59b44847b379578588920cA78FbF26c0B4956C
REGISTRY=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
KUDOS=0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921
RPC=${READ_RPC:-https://bsc-dataseed.bnbchain.org}
forge build --silent
BC=$(forge inspect AgentKudosCard bytecode)
ARGS=$(cast abi-encode "c(address,address)" $REGISTRY $KUDOS)
INIT=$BC${ARGS:2}
SALT=$(cast keccak "AgentKudosCard.v1")
echo "$SALT" > deploy/card/salt.txt
echo "${SALT}${INIT:2}" > deploy/card/create2_calldata.hex
echo "$ARGS" > deploy/card/constructor_args.hex
ADDR=$(cast create2 --deployer $FACTORY --salt $SALT --init-code $INIT | awk '{print $1}' | tail -1)
echo "$ADDR" > deploy/card/predicted_address.txt
echo "predicted AgentKudosCard address: $ADDR"
echo "calldata bytes: $(( ($(wc -c < deploy/card/create2_calldata.hex) - 3) / 2 ))"
echo "estimated gas: $(cast estimate --rpc-url $RPC $FACTORY $(cat deploy/card/create2_calldata.hex))"
echo "code at predicted address (should be 0x): $(cast code --rpc-url $RPC $ADDR)"
