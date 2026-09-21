import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  AuthorityType,
  ExtensionType,
  TOKEN_2022_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createInitializeMintInstruction,
  createInitializeNonTransferableMintInstruction,
  createMintToInstruction,
  createSetAuthorityInstruction,
  getAssociatedTokenAddressSync,
  getMintLen,
} from "@solana/spl-token";
import { Buffer } from "buffer";
import { Wallet } from "./api";

const RPC_URL = process.env.NEXT_PUBLIC_SOLANA_RPC_URL || "https://api.devnet.solana.com";
const MEMO_PROGRAM = new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");

type PhantomProvider = {
  isPhantom?: boolean;
  publicKey?: PublicKey;
  connect: () => Promise<{ publicKey: PublicKey }>;
  signMessage: (message: Uint8Array, display?: "utf8") => Promise<{ signature: Uint8Array }>;
  signAndSendTransaction: (transaction: Transaction) => Promise<{ signature: string }>;
};

declare global {
  interface Window {
    phantom?: { solana?: PhantomProvider };
  }
}

function provider(): PhantomProvider {
  const value = window.phantom?.solana;
  if (!value?.isPhantom) throw new Error("Установите Phantom Wallet и переключите сеть на Devnet");
  return value;
}

function bytesToBase64(value: Uint8Array) {
  let binary = "";
  value.forEach((byte) => { binary += String.fromCharCode(byte); });
  return window.btoa(binary);
}

export function shortWallet(address: string) {
  return `${address.slice(0, 4)}…${address.slice(-4)}`;
}

export async function connectAndVerifyWallet() {
  const phantom = provider();
  const { publicKey } = await phantom.connect();
  const address = publicKey.toBase58();
  const challenge = await Wallet.challenge(address);
  const encoded = new TextEncoder().encode(challenge.message);
  const signed = await phantom.signMessage(encoded, "utf8");
  await Wallet.verify(address, challenge.message, bytesToBase64(signed.signature));
  return address;
}

export async function mintNonTransferableTicket(eventId: number, registrationId: number, expectedWallet: string) {
  const phantom = provider();
  const { publicKey: owner } = await phantom.connect();
  if (owner.toBase58() !== expectedWallet) throw new Error("В Phantom подключён другой кошелёк");

  const connection = new Connection(RPC_URL, "confirmed");
  const mint = Keypair.generate();
  const mintLength = getMintLen([ExtensionType.NonTransferable]);
  const rent = await connection.getMinimumBalanceForRentExemption(mintLength);
  const tokenAccount = getAssociatedTokenAddressSync(mint.publicKey, owner, false, TOKEN_2022_PROGRAM_ID);
  const transaction = new Transaction().add(
    SystemProgram.createAccount({ fromPubkey: owner, newAccountPubkey: mint.publicKey, space: mintLength, lamports: rent, programId: TOKEN_2022_PROGRAM_ID }),
    createInitializeNonTransferableMintInstruction(mint.publicKey, TOKEN_2022_PROGRAM_ID),
    createInitializeMintInstruction(mint.publicKey, 0, owner, null, TOKEN_2022_PROGRAM_ID),
    createAssociatedTokenAccountIdempotentInstruction(owner, tokenAccount, owner, mint.publicKey, TOKEN_2022_PROGRAM_ID),
    createMintToInstruction(mint.publicKey, tokenAccount, owner, 1, [], TOKEN_2022_PROGRAM_ID),
    createSetAuthorityInstruction(mint.publicKey, owner, AuthorityType.MintTokens, null, [], TOKEN_2022_PROGRAM_ID),
    new TransactionInstruction({
      keys: [{ pubkey: owner, isSigner: true, isWritable: false }, { pubkey: mint.publicKey, isSigner: false, isWritable: false }],
      programId: MEMO_PROGRAM,
      data: Buffer.from(`evently:v1:${eventId}:${registrationId}`, "utf8"),
    }),
  );
  const latest = await connection.getLatestBlockhash("confirmed");
  transaction.feePayer = owner;
  transaction.recentBlockhash = latest.blockhash;
  transaction.partialSign(mint);
  const sent = await phantom.signAndSendTransaction(transaction);
  await connection.confirmTransaction({ signature: sent.signature, ...latest }, "confirmed");
  return { signature: sent.signature, tokenAddress: mint.publicKey.toBase58() };
}

export async function createCheckInProof(memo: string, expectedWallet: string) {
  const phantom = provider();
  const { publicKey: organizer } = await phantom.connect();
  if (organizer.toBase58() !== expectedWallet) throw new Error("В Phantom подключён другой кошелёк организатора");

  const connection = new Connection(RPC_URL, "confirmed");
  const latest = await connection.getLatestBlockhash("confirmed");
  const transaction = new Transaction().add(
    new TransactionInstruction({
      keys: [ { pubkey: organizer, isSigner: true, isWritable: false } ],
      programId: MEMO_PROGRAM,
      data: Buffer.from(memo, "utf8"),
    }),
  );
  transaction.feePayer = organizer;
  transaction.recentBlockhash = latest.blockhash;
  const sent = await phantom.signAndSendTransaction(transaction);
  await connection.confirmTransaction({ signature: sent.signature, ...latest }, "confirmed");
  return sent.signature;
}
