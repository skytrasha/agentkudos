// Live AgentKudos deployment on BSC (tx 0x8c5bd1e586a50e7f1574fda4a68c3bf7bd5adda2ebc3ba7532c074686b13b061).
export const CONFIG = {
  CHAIN_ID: 56,
  CHAIN_HEX: "0x38",
  READ_RPC: "https://bsc-rpc.publicnode.com",
  CONTRACT: "0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921",
  DEPLOY_BLOCK: 134458942,
  REGISTRY: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
  TOKENS: {
    BNB: { address: "0x0000000000000000000000000000000000000000", decimals: 18 },
    USDT: { address: "0x55d398326f99059fF775485246999027B3197955", decimals: 18 },
    USDC: { address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", decimals: 18 },
  },
  EXPLORER: "https://bscscan.com",
};
