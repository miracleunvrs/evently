import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const cluster=process.argv[2]||'localnet';
if (!['localnet','devnet'].includes(cluster)) throw new Error('Invalid cluster');
const run=JSON.parse(fs.readFileSync(path.join(root,`evidence/${cluster}-run.json`)));
const rows=run.transactions.map(t=>({label:t.label,signature:t.signature,slot:t.slot,fee_lamports:t.fee_lamports,signers:t.accounts.filter(a=>a.signer).map(a=>a.address),writable_accounts:t.accounts.filter(a=>a.writable).map(a=>a.address),programs:[...new Set(t.instructions.map(i=>i.programId))],instructions:t.instructions.map(i=>({program:i.program||'custom',program_id:i.programId,type:i.parsed?.type||'raw instruction',data:i.parsed||i.data})),balance_delta_lamports:t.post_balances.map((v,i)=>v-t.pre_balances[i])}));
fs.writeFileSync(path.join(root,`evidence/${cluster}-transaction-analysis.json`),JSON.stringify(rows,null,2));
console.log(`Analyzed ${rows.length} confirmed ${cluster} transactions`);
