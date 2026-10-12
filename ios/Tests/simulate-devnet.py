#!/usr/bin/env python3
"""Simulates the ticket transaction built by SolanaKit.swift on Solana Devnet and applies the API's ticket checks.

Nothing is signed or sent: the cluster runs the transaction with signature checks off, as if the given wallet had
approved it, and returns the accounts it would create. The wallet only has to hold enough Devnet SOL for rent.

    sh ios/Tests/run.sh && python3 ios/Tests/simulate-devnet.py <funded devnet wallet address>
"""
import json, os, subprocess, sys, urllib.request

RPC = os.environ.get("SOLANA_RPC_URL", "https://api.devnet.solana.com")
TOKEN_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

def rpc(method, params):
    request = urllib.request.Request(RPC, data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                                     headers={"Content-Type": "application/json"})
    body = json.load(urllib.request.urlopen(request, timeout=30))
    if "error" in body: sys.exit(f"RPC error: {body['error']}")
    return body["result"]

owner = sys.argv[1]
binary = os.path.join(os.environ.get("TMPDIR", "/tmp"), "evently-solanakit-tests")
rent = rpc("getMinimumBalanceForRentExemption", [170])
wire, mint, token_account, memo = subprocess.check_output([binary, "--ticket-for", owner, str(rent)], text=True).split()
result = rpc("simulateTransaction", [wire, {"encoding": "base64", "sigVerify": False, "replaceRecentBlockhash": True, "commitment": "confirmed",
                                            "accounts": {"encoding": "jsonParsed", "addresses": [mint, token_account]}}])["value"]
if result["err"]:
    print("\n".join(result.get("logs") or []))
    sys.exit(f"FAIL simulation error: {result['err']}")
mint_account, holding = result["accounts"]
mint_info = mint_account["data"]["parsed"]["info"]
holding_info = holding["data"]["parsed"]["info"]
checks = {
    "mint is owned by Token-2022": mint_account["owner"] == TOKEN_2022,
    "mint is non-transferable": "nonTransferable" in [item["extension"] for item in mint_info.get("extensions", [])],
    "mint authority is removed": mint_info["mintAuthority"] is None,
    "supply is exactly one, no decimals": mint_info["supply"] == "1" and mint_info["decimals"] == 0,
    "the wallet holds the ticket": holding_info["owner"] == owner and holding_info["mint"] == mint and holding_info["tokenAmount"]["amount"] == "1",
    "memo names the registration": any(memo in line for line in result["logs"]),
}
for label, passed in checks.items(): print(("ok   " if passed else "FAIL ") + label)
print(f"units consumed: {result.get('unitsConsumed')}, rent for the mint: {rent} lamports")
sys.exit(0 if all(checks.values()) else 1)
