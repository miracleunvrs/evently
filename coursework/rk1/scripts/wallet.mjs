import { Keypair, Connection, LAMPORTS_PER_SOL } from '@solana/web3.js';
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const dir = path.join(root, '.secrets');
fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
for (const name of ['payer', 'recipient', 'evently_lab', 'hello_evently']) {
 const file = path.join(dir, `${name}.json`);
 if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify(Array.from(Keypair.generate().secretKey)), { mode: 0o600 });
}
const wallet = Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(path.join(dir, 'payer.json')))));
const connection = new Connection('https://api.devnet.solana.com', { commitment:'confirmed', disableRetryOnRateLimit:true });
const result = { cluster:'devnet', address:wallet.publicKey.toBase58(), balance:await connection.getBalance(wallet.publicKey), checked_at:new Date().toISOString() };
if (process.argv.includes('--airdrop') && result.balance < LAMPORTS_PER_SOL) {
 try { result.airdrop_signature = await connection.requestAirdrop(wallet.publicKey, 2 * LAMPORTS_PER_SOL); }
 catch (error) { result.airdrop_error = error.message; }
}
fs.writeFileSync(path.join(root, 'evidence/wallet.json'), JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
