import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { Keypair } from '@solana/web3.js';

const root = path.resolve(import.meta.dirname, '..');
const key = Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(path.join(root, '.secrets/evently_lab.json')))));
const address = key.publicKey.toBase58();
const sourcePath = path.join(root, 'programs/evently_lab/src/lib.rs');
const configPath = path.join(root, 'Anchor.toml');
const source = fs.readFileSync(sourcePath, 'utf8');
const config = fs.readFileSync(configPath, 'utf8');
assert.equal((source.match(/declare_id!\("[1-9A-HJ-NP-Za-km-z]+"\)/g) || []).length, 1);
assert.equal((config.match(/^evently_lab = "[1-9A-HJ-NP-Za-km-z]+"$/gm) || []).length, 2);
fs.writeFileSync(sourcePath, source.replace(/declare_id!\("[1-9A-HJ-NP-Za-km-z]+"\)/, `declare_id!("${address}")`));
fs.writeFileSync(configPath, config.replace(/^evently_lab = "[1-9A-HJ-NP-Za-km-z]+"$/gm, `evently_lab = "${address}"`));
console.log(`Program ID synchronized: ${address}. Rebuild the program and IDL before deployment.`);
