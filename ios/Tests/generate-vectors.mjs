// Regenerates ios/Tests/vectors.json from the same libraries the web client uses.
// Run from the repo root: node ios/Tests/generate-vectors.mjs
import { createHash } from "node:crypto";
import { writeFileSync, readFileSync, existsSync } from "node:fs";
import bs58 from "bs58";
import { Keypair, PublicKey, SystemProgram, Transaction, TransactionInstruction } from "@solana/web3.js";
import {
  AuthorityType, ExtensionType, TOKEN_2022_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction, createInitializeMintInstruction,
  createInitializeNonTransferableMintInstruction, createMintToInstruction,
  createSetAuthorityInstruction, getAssociatedTokenAddressSync, getMintLen,
} from "@solana/spl-token";

const out = new URL("./vectors.json", import.meta.url);
const previous = existsSync(out) ? JSON.parse(readFileSync(out, "utf8")) : {};
const bytes = (seed, length) => {
  let data = Buffer.alloc(0);
  for (let i = 0; data.length < length; i++) data = Buffer.concat([data, createHash("sha256").update(`${seed}:${i}`).digest()]);
  return data.subarray(0, length);
};
const hex = (value) => Buffer.from(value).toString("hex");

const base58 = [0, 1, 2, 31, 32, 33, 64, 100].map((length, index) => {
  const data = index % 2 ? bytes(`b58-${index}`, length) : Buffer.concat([Buffer.alloc(Math.min(3, length)), bytes(`b58-${index}`, Math.max(0, length - 3))]);
  return { hex: hex(data), base58: bs58.encode(data) };
});

const onCurve = Array.from({ length: 400 }, (_, index) => {
  const data = index < 200 ? bytes(`curve-${index}`, 32) : Keypair.fromSeed(bytes(`key-${index}`, 32)).publicKey.toBytes();
  return { hex: hex(data), onCurve: PublicKey.isOnCurve(data) };
});

const owner = Keypair.fromSeed(bytes("owner", 32));
const mint = Keypair.fromSeed(bytes("mint", 32));
const organizer = Keypair.fromSeed(bytes("organizer", 32));
const associated = Array.from({ length: 12 }, (_, index) => {
  const wallet = Keypair.fromSeed(bytes(`wallet-${index}`, 32)).publicKey;
  const token = Keypair.fromSeed(bytes(`token-${index}`, 32)).publicKey;
  return { owner: wallet.toBase58(), mint: token.toBase58(), address: getAssociatedTokenAddressSync(token, wallet, false, TOKEN_2022_PROGRAM_ID).toBase58() };
});

// Instructions as a validator sees them: signer and writable flags come from the compiled message, so an account
// that signs or is written anywhere in the transaction carries that flag in every instruction.
const describe = (source) => Transaction.from(source.serialize({ requireAllSignatures: false, verifySignatures: false })).instructions.map((instruction) => ({
  program: instruction.programId.toBase58(),
  keys: instruction.keys.map((key) => ({ pubkey: key.pubkey.toBase58(), signer: key.isSigner, writable: key.isWritable })),
  data: hex(instruction.data),
}));

const mintLength = getMintLen([ExtensionType.NonTransferable]);
const rent = 2074080;
const blockhash = bs58.encode(bytes("blockhash", 32));
const memo = "evently:v1:42:1337";
const tokenAccount = getAssociatedTokenAddressSync(mint.publicKey, owner.publicKey, false, TOKEN_2022_PROGRAM_ID);
const ticket = new Transaction().add(
  SystemProgram.createAccount({ fromPubkey: owner.publicKey, newAccountPubkey: mint.publicKey, space: mintLength, lamports: rent, programId: TOKEN_2022_PROGRAM_ID }),
  createInitializeNonTransferableMintInstruction(mint.publicKey, TOKEN_2022_PROGRAM_ID),
  createInitializeMintInstruction(mint.publicKey, 0, owner.publicKey, null, TOKEN_2022_PROGRAM_ID),
  createAssociatedTokenAccountIdempotentInstruction(owner.publicKey, tokenAccount, owner.publicKey, mint.publicKey, TOKEN_2022_PROGRAM_ID),
  createMintToInstruction(mint.publicKey, tokenAccount, owner.publicKey, 1, [], TOKEN_2022_PROGRAM_ID),
  createSetAuthorityInstruction(mint.publicKey, owner.publicKey, AuthorityType.MintTokens, null, [], TOKEN_2022_PROGRAM_ID),
  new TransactionInstruction({
    keys: [{ pubkey: owner.publicKey, isSigner: true, isWritable: false }, { pubkey: mint.publicKey, isSigner: false, isWritable: false }],
    programId: new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
    data: Buffer.from(memo, "utf8"),
  }),
);
ticket.feePayer = owner.publicKey;
ticket.recentBlockhash = blockhash;

const checkInMemo = "evently:checkin:v1:7:1337";
const checkIn = new Transaction().add(new TransactionInstruction({
  keys: [{ pubkey: organizer.publicKey, isSigner: true, isWritable: false }],
  programId: new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
  data: Buffer.from(checkInMemo, "utf8"),
}));
checkIn.feePayer = organizer.publicKey;
checkIn.recentBlockhash = blockhash;

writeFileSync(out, JSON.stringify({
  base58, onCurve, associated,
  ticket: {
    owner: owner.publicKey.toBase58(), mintSeed: hex(bytes("mint", 32)), mint: mint.publicKey.toBase58(),
    eventId: 42, registrationId: 1337, rent, mintLength, blockhash,
    tokenAccount: tokenAccount.toBase58(), instructions: describe(ticket),
  },
  checkIn: { organizer: organizer.publicKey.toBase58(), memo: checkInMemo, blockhash, instructions: describe(checkIn) },
  // NaCl box vectors come from libsodium (see generate-box-vectors.rb) and are kept as they are.
  box: previous.box ?? [],
}, null, 1) + "\n");
console.log(`mintLength=${mintLength}`, describe(ticket).map((item) => `${item.program.slice(0, 6)}:${item.data.length / 2}b:${item.keys.length}k`).join(" "));
