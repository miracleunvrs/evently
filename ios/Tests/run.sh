#!/bin/sh
# Builds SolanaKit.swift and PhantomLink.swift for macOS and checks them against vectors.json,
# then lets @solana/web3.js re-parse the transactions.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/evently-solanakit-tests"
swiftc -O ../Evently/Evently/SolanaKit.swift ../Evently/Evently/PhantomLink.swift main.swift -o "$out"
"$out" vectors.json | tee "$out.log" | grep -v '_TX '
if command -v node >/dev/null 2>&1 && [ -d ../../node_modules/@solana/web3.js ]; then
  node verify-transactions.mjs "$out.log"
fi
