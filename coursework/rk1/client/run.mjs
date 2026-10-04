import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { Connection, Keypair, PublicKey, SystemProgram, Transaction, TransactionInstruction, sendAndConfirmTransaction } from '@solana/web3.js';
import { AnchorProvider, Program, Wallet } from '@coral-xyz/anchor';
import * as token from '@solana/spl-token';
import { createInitializeInstruction, pack } from '@solana/spl-token-metadata';

const root = path.resolve(import.meta.dirname, '..');
const cluster = process.argv[2] || 'localnet';
if (!['localnet','devnet'].includes(cluster)) throw new Error('Only localnet or devnet is allowed');
const rpc = cluster === 'devnet' ? 'https://api.devnet.solana.com' : 'http://127.0.0.1:8899';
const connection = new Connection(rpc, { commitment: 'confirmed', disableRetryOnRateLimit: true });
const loadKey = name => Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(path.join(root, '.secrets', name + '.json')))));
const payer = loadKey('payer');
const recipient = loadKey('recipient');
const result = { cluster, rpc, generated_at: new Date().toISOString(), payer: payer.publicKey.toBase58(), recipient: recipient.publicKey.toBase58(), transactions: [], checks: [] };
const save = () => fs.writeFileSync(path.join(root, 'evidence', `${cluster}-run.json`), JSON.stringify(result,null,2));
async function record(label, signature) {
 const tx = await connection.getParsedTransaction(signature, { commitment: 'confirmed', maxSupportedTransactionVersion: 0 });
 assert(tx && tx.meta.err === null, label + ' must be confirmed and successful');
 const row = { label, signature, slot: tx.slot, fee_lamports: tx.meta.fee, instructions: tx.transaction.message.instructions, accounts: tx.transaction.message.accountKeys.map(a => ({ address:a.pubkey.toBase58(), signer:a.signer, writable:a.writable })), logs:tx.meta.logMessages, pre_balances:tx.meta.preBalances, post_balances:tx.meta.postBalances };
 if (cluster === 'devnet') row.explorer = `https://explorer.solana.com/tx/${signature}?cluster=devnet`;
 result.transactions.push(row); save(); console.log(label + ': ' + signature);
}
async function send(label, instructions, extra = []) {
 const signature = await sendAndConfirmTransaction(connection, new Transaction().add(...instructions), [payer,...extra], {commitment:'confirmed'});
 await record(label, signature); return signature;
}
async function reject(label, action, expected) {
 let error;
 try { await action(); } catch (e) { error=e; }
 assert(error, label + ' unexpectedly succeeded');
 assert(expected.test(String(error)), label + ': unexpected error: ' + error);
 result.checks.push({ label, passed:true, detail:String(error).slice(0,900) }); save();
}

result.genesis_hash = await connection.getGenesisHash();
result.initial_balance_lamports = await connection.getBalance(payer.publicKey);
save();
await send('week1_sol_transfer', [SystemProgram.transfer({ fromPubkey:payer.publicKey, toPubkey:recipient.publicKey, lamports:1_000_000 })]);

const hello = loadKey('hello_evently').publicKey;
assert((await connection.getAccountInfo(hello))?.executable, 'Deploy hello_evently first');
result.hello_program = hello.toBase58();
await send('week4_hello_program', [new TransactionInstruction({programId:hello, keys:[{pubkey:payer.publicKey,isSigner:true,isWritable:false}],data:Buffer.from('evently-rk1')})]);
await reject('hello_rejects_invalid_instruction', () => send('invalid', [new TransactionInstruction({programId:hello, keys:[{pubkey:payer.publicKey,isSigner:true,isWritable:false}],data:Buffer.from('wrong')})]), /invalid instruction data/i);

const idl = JSON.parse(fs.readFileSync(path.join(root,'target/idl/evently_lab.json')));
const provider = new AnchorProvider(connection,new Wallet(payer),{commitment:'confirmed'});
const program = new Program(idl,provider);
const [counter,bump] = PublicKey.findProgramAddressSync([Buffer.from('counter'),payer.publicKey.toBuffer()],program.programId);
const [profile,profileBump] = PublicKey.findProgramAddressSync([Buffer.from('profile'),payer.publicKey.toBuffer()],program.programId);
result.anchor_program = program.programId.toBase58();
result.counter = { address:counter.toBase58(), seeds:['counter',payer.publicKey.toBase58()], bump };
result.profile = { address:profile.toBase58(), seeds:['profile',payer.publicKey.toBase58()], bump:profileBump };
if (!await connection.getAccountInfo(counter)) await record('week5_initialize_counter', await program.methods.initializeCounter().accounts({authority:payer.publicKey}).rpc());
const before=(await program.account.counter.fetch(counter)).count.toNumber();
await record('week5_increment',await program.methods.increment().accounts({authority:payer.publicKey}).rpc());
const after=(await program.account.counter.fetch(counter)).count.toNumber();
assert.equal(after,before+1); result.counter.before=before; result.counter.after=after;
const otherProgram=new Program(idl,new AnchorProvider(connection,new Wallet(recipient),{commitment:'confirmed'}));
await reject('counter_rejects_other_authority',()=>otherProgram.methods.increment().accountsStrict({counter,authority:recipient.publicKey}).rpc(), /ConstraintSeeds|ConstraintHasOne/);
if (!await connection.getAccountInfo(profile)) await record('week6_create_profile',await program.methods.createProfile('Evently Student','Solana course project').accounts({authority:payer.publicKey}).rpc());
await record('week6_update_profile',await program.methods.updateProfile('Evently Student','Organizer profile for the Evently RK1 demo').accounts({authority:payer.publicKey}).rpc());
const stored=await program.account.profile.fetch(profile);
assert.equal(stored.authority.toBase58(),payer.publicKey.toBase58());
assert.equal(stored.name,'Evently Student');
result.profile.data={authority:stored.authority.toBase58(),name:stored.name,bio:stored.bio};
result.profile.account_owner=(await connection.getAccountInfo(profile)).owner.toBase58();
await reject('profile_rejects_other_authority',()=>otherProgram.methods.updateProfile('Intruder','Unauthorized').accountsStrict({profile,authority:recipient.publicKey}).rpc(),/ConstraintSeeds|ConstraintHasOne/);
await reject('profile_rejects_oversized_name',()=>program.methods.updateProfile('x'.repeat(33),'').accounts({authority:payer.publicKey}).rpc(),/InvalidName/);

const mint=Keypair.generate();
const metadata={updateAuthority:payer.publicKey,mint:mint.publicKey,name:'Evently Lab Credit',symbol:'ELAB',uri:'https://raw.githubusercontent.com/miracleunvrs/evently/main/public/metadata/evently-lab.json',additionalMetadata:[]};
const mintLength=token.getMintLen([token.ExtensionType.MetadataPointer]);
const rent=await connection.getMinimumBalanceForRentExemption(mintLength+token.TYPE_SIZE+token.LENGTH_SIZE+pack(metadata).length);
const sourceAta=token.getAssociatedTokenAddressSync(mint.publicKey,payer.publicKey,false,token.TOKEN_2022_PROGRAM_ID);
const destinationAta=token.getAssociatedTokenAddressSync(mint.publicKey,recipient.publicKey,false,token.TOKEN_2022_PROGRAM_ID);
await send('week7_create_mint_metadata',[
 SystemProgram.createAccount({fromPubkey:payer.publicKey,newAccountPubkey:mint.publicKey,space:mintLength,lamports:rent,programId:token.TOKEN_2022_PROGRAM_ID}),
 token.createInitializeMetadataPointerInstruction(mint.publicKey,payer.publicKey,mint.publicKey,token.TOKEN_2022_PROGRAM_ID),
 token.createInitializeMintInstruction(mint.publicKey,2,payer.publicKey,null,token.TOKEN_2022_PROGRAM_ID),
 createInitializeInstruction({programId:token.TOKEN_2022_PROGRAM_ID,metadata:mint.publicKey,updateAuthority:payer.publicKey,mint:mint.publicKey,mintAuthority:payer.publicKey,name:metadata.name,symbol:metadata.symbol,uri:metadata.uri}),
],[mint]);
await send('week7_issue_tokens',[
 token.createAssociatedTokenAccountIdempotentInstruction(payer.publicKey,sourceAta,payer.publicKey,mint.publicKey,token.TOKEN_2022_PROGRAM_ID),
 token.createAssociatedTokenAccountIdempotentInstruction(payer.publicKey,destinationAta,recipient.publicKey,mint.publicKey,token.TOKEN_2022_PROGRAM_ID),
 token.createMintToInstruction(mint.publicKey,sourceAta,payer.publicKey,100_000,[],token.TOKEN_2022_PROGRAM_ID),
 token.createSetAuthorityInstruction(mint.publicKey,payer.publicKey,token.AuthorityType.MintTokens,null,[],token.TOKEN_2022_PROGRAM_ID)
]);
await send('week7_transfer_tokens',[token.createTransferCheckedInstruction(sourceAta,mint.publicKey,destinationAta,payer.publicKey,2_500,2,[],token.TOKEN_2022_PROGRAM_ID)]);
const source=await token.getAccount(connection,sourceAta,'confirmed',token.TOKEN_2022_PROGRAM_ID);
const dest=await token.getAccount(connection,destinationAta,'confirmed',token.TOKEN_2022_PROGRAM_ID);
const mintState=await token.getMint(connection,mint.publicKey,'confirmed',token.TOKEN_2022_PROGRAM_ID);
const storedMetadata=await token.getTokenMetadata(connection,mint.publicKey,'confirmed',token.TOKEN_2022_PROGRAM_ID);
assert.equal(source.amount,97_500n); assert.equal(dest.amount,2_500n); assert.equal(mintState.supply,100_000n); assert.equal(mintState.mintAuthority,null); assert.equal(storedMetadata.name,metadata.name);
result.token={mint:mint.publicKey.toBase58(),decimals:2,supply_raw:mintState.supply.toString(),source_balance_raw:source.amount.toString(),recipient_balance_raw:dest.amount.toString(),mint_authority:null,metadata:{name:storedMetadata.name,symbol:storedMetadata.symbol,uri:storedMetadata.uri}};
result.checks.push({label:'token_supply_transfer_metadata_verified',passed:true});
result.completed_at=new Date().toISOString(); save(); console.log('All lab checks passed');
