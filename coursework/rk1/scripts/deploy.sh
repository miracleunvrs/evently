#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cluster="${1:-localnet}"
case "$cluster" in
  localnet) rpc='http://127.0.0.1:8899' ;;
  devnet) rpc='https://api.devnet.solana.com' ;;
  *) echo 'Only localnet and devnet are supported' >&2; exit 2 ;;
esac
for program in hello_evently evently_lab; do
  solana --url "$rpc" --keypair .secrets/payer.json program deploy \
    --program-id ".secrets/$program.json" "target/deploy/$program.so" \
    --output json > "evidence/$cluster-deploy-$program.json"
done
