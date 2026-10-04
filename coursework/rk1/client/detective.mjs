import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { Connection, SystemProgram } from '@solana/web3.js';

// Read-only investigation of a public transaction, never presented as our own.
const connection = new Connection('https://api.devnet.solana.com', {
  commitment: 'confirmed', disableRetryOnRateLimit: true,
});
let signature = process.argv[2];
if (!signature) {
  const recent = await connection.getSignaturesForAddress(SystemProgram.programId, { limit: 5 });
  signature = recent.find(tx => tx.err === null)?.signature;
}
assert(signature, 'No successful public transaction found');
const tx = await connection.getParsedTransaction(signature, { maxSupportedTransactionVersion: 0 });
assert(tx && tx.meta.err === null, 'Transaction must exist and have succeeded');
const result = {
  cluster: 'devnet', origin: 'Public third-party transaction, read-only analysis; not sent by Evently',
  retrieved_at: new Date().toISOString(), signature, slot: tx.slot,
  explorer: `https://explorer.solana.com/tx/${signature}?cluster=devnet`,
  fee_lamports: tx.meta.fee,
  accounts: tx.transaction.message.accountKeys.map((a, i) => ({
    address: a.pubkey.toBase58(), signer: a.signer, writable: a.writable,
    balance_before: tx.meta.preBalances[i], balance_after: tx.meta.postBalances[i],
    delta_lamports: tx.meta.postBalances[i] - tx.meta.preBalances[i],
  })),
  instructions: tx.transaction.message.instructions,
  inner_instructions: tx.meta.innerInstructions,
  logs: tx.meta.logMessages,
};
fs.writeFileSync(path.resolve(import.meta.dirname, '../evidence/devnet-detective.json'), JSON.stringify(result, null, 2));
console.log(result.explorer);
console.log(`Confirmed slot ${result.slot}, ${result.accounts.length} accounts, ${result.instructions.length} instructions`);
