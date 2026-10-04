import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { Connection, Keypair, PublicKey, SystemProgram, Transaction, TransactionInstruction, sendAndConfirmTransaction } from '@solana/web3.js';
import * as token from '@solana/spl-token';
const root=path.resolve(import.meta.dirname,'..');
const api='http://127.0.0.1:8001';
const chain=new Connection('http://127.0.0.1:8899','confirmed');
const key=name=>Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(path.join(root,'.secrets',name+'.json')))));
const guestWallet=key('payer'), organizerWallet=key('recipient');
const report={cluster:'localnet',api,started_at:new Date().toISOString(),checks:[],signatures:{}};
const check=(label,actual,expected)=>{assert.equal(actual,expected,label);report.checks.push({label,actual,expected,passed:true});};
async function call(route,method='GET',body,access){
 const response=await fetch(api+route,{method,headers:{'Content-Type':'application/json',...(access?{Authorization:`Bearer ${access}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 return {status:response.status,data:response.status===204?null:await response.json()};
}
const suffix=Date.now();
const password=crypto.randomBytes(24).toString('base64url');
const accountFile=path.join(root,'.secrets','mvp-accounts.json');
const accounts=fs.existsSync(accountFile)?JSON.parse(fs.readFileSync(accountFile)):[];
for(const role of ['visitor','organizer','admin']){
 if(accounts.some(a=>a.role===role)) continue;
 const email=`rk1-${role}-${suffix}@example.test`;
 const registered=await call('/auth/register','POST',{name:`RK1 ${role}`,email,password,password_confirmation:password});
 check(`register_${role}`,registered.status,201);
 check(`registration_never_grants_${role}`,registered.data.user.role,'visitor');
 accounts.push({role,email,password,id:registered.data.user.id});
}
const seed=spawnSync('docker',['exec','-i','evently-rk1-api','bin/rails','runner','abort "Only isolated RK1 database allowed" unless Rails.env.development? && ActiveRecord::Base.connection_db_config.database == "evently_rk1"; JSON.parse(STDIN.read).each { |row| User.find(row.fetch("id")).update!(role: row.fetch("role")) }'],{input:JSON.stringify(accounts),encoding:'utf8'});
assert.equal(seed.status,0,seed.stderr);
fs.writeFileSync(path.join(root,'.secrets','mvp-accounts.json'),JSON.stringify(accounts,null,2),{mode:0o600});
for (const account of accounts) { const login=await call('/auth/login','POST',account); check(`login_${account.role}`,login.status,200);check(`role_${account.role}`,login.data.user.role,account.role);account.access=login.data.access_token; }
const [guest,organizer,admin]=accounts;
async function verifyWallet(account,wallet){
 const challenge=await call('/wallet/challenge','POST',{wallet_address:wallet.publicKey.toBase58()},account.access);check(`wallet_challenge_${account.role}`,challenge.status,200);
 const secret=crypto.createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),Buffer.from(wallet.secretKey.subarray(0,32))]),format:'der',type:'pkcs8'});
 const signature=crypto.sign(null,Buffer.from(challenge.data.message),secret).toString('base64');
 const verified=await call('/wallet/verify','POST',{wallet_address:wallet.publicKey.toBase58(),message:challenge.data.message,signature},account.access);check(`wallet_verified_${account.role}`,verified.status,200);
}
await verifyWallet(guest,guestWallet);await verifyWallet(organizer,organizerWallet);
const event=await call('/events','POST',{title:'Evently RK1 integration demo',starts_at:new Date(Date.now()+86400000).toISOString(),capacity:1,city:'Алматы',place:'Учебная площадка'},organizer.access);check('organizer_creates_event',event.status,201);
report.event_id=event.data.id;
const reserved=await call(`/events/${event.data.id}/register`,'POST',{},guest.access);check('guest_reserves_ticket',reserved.status,201);
const ticket=reserved.data;
const mint=Keypair.generate();const length=token.getMintLen([token.ExtensionType.NonTransferable]);
const ata=token.getAssociatedTokenAddressSync(mint.publicKey,guestWallet.publicKey,false,token.TOKEN_2022_PROGRAM_ID);
const memoProgram=new PublicKey('MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr');
const signature=await sendAndConfirmTransaction(chain,new Transaction().add(
 SystemProgram.createAccount({fromPubkey:guestWallet.publicKey,newAccountPubkey:mint.publicKey,space:length,lamports:await chain.getMinimumBalanceForRentExemption(length),programId:token.TOKEN_2022_PROGRAM_ID}),
 token.createInitializeNonTransferableMintInstruction(mint.publicKey,token.TOKEN_2022_PROGRAM_ID),
 token.createInitializeMintInstruction(mint.publicKey,0,guestWallet.publicKey,null,token.TOKEN_2022_PROGRAM_ID),
 token.createAssociatedTokenAccountIdempotentInstruction(guestWallet.publicKey,ata,guestWallet.publicKey,mint.publicKey,token.TOKEN_2022_PROGRAM_ID),
 token.createMintToInstruction(mint.publicKey,ata,guestWallet.publicKey,1,[],token.TOKEN_2022_PROGRAM_ID),
 token.createSetAuthorityInstruction(mint.publicKey,guestWallet.publicKey,token.AuthorityType.MintTokens,null,[],token.TOKEN_2022_PROGRAM_ID),
 new TransactionInstruction({programId:memoProgram,keys:[{pubkey:guestWallet.publicKey,isSigner:true,isWritable:false},{pubkey:mint.publicKey,isSigner:false,isWritable:false}],data:Buffer.from(`evently:v1:${event.data.id}:${ticket.registration_id}`)})
),[guestWallet,mint],{commitment:'confirmed'});
report.signatures.mint=signature;report.mint=mint.publicKey.toBase58();
const confirmation=await call(`/tickets/${ticket.id}/blockchain`,'POST',{solana_signature:signature,token_address:mint.publicKey.toBase58()},guest.access);check('rails_verifies_real_token2022',confirmation.status,200);check('ticket_is_confirmed',confirmation.data.blockchain_status,'confirmed');
const stolen=await call(`/events/${event.data.id}/guests`,'GET',null,guest.access);check('guest_cannot_read_guest_list',stolen.status,404);
const wrongCreator=await call('/events','POST',{title:'Unauthorized'},guest.access);check('guest_cannot_create_event',wrongCreator.status,403);
const wait=await call(`/events/${event.data.id}/waitlist`,'POST',{},admin.access);check('full_event_accepts_waitlist',wait.status,201);
const prepared=await call('/check-in/prepare','POST',{code:ticket.code},organizer.access);check('checkin_prepared',prepared.status,200);
const proof=await sendAndConfirmTransaction(chain,new Transaction().add(new TransactionInstruction({programId:memoProgram,keys:[{pubkey:organizerWallet.publicKey,isSigner:true,isWritable:false}],data:Buffer.from(prepared.data.memo)})),[organizerWallet],{commitment:'confirmed'});
report.signatures.checkin=proof;
const entrance=await call('/check-in','POST',{code:ticket.code,check_in_signature:proof},organizer.access);check('first_checkin_accepted',entrance.status,200);
const duplicate=await call('/check-in','POST',{code:ticket.code,check_in_signature:proof},organizer.access);check('duplicate_checkin_rejected',duplicate.status,409);
const canceled=await call(`/registrations/${ticket.registration_id}`,'DELETE',null,guest.access);check('used_ticket_cannot_be_canceled',canceled.status,409);
const stats=await call(`/events/${event.data.id}/stats`,'GET',null,organizer.access);check('one_registration',stats.data.registrations,1);check('one_visit',stats.data.visits,1);
report.stats=stats.data;report.finished_at=new Date().toISOString();
fs.writeFileSync(path.join(root,'evidence/mvp-integration.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
