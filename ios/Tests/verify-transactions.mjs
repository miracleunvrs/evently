// Independent check: @solana/web3.js parses the transactions built by SolanaKit.swift and compares them with vectors.json.
import { readFileSync } from "node:fs";
import { ed25519 } from "@noble/curves/ed25519";
import { Transaction } from "@solana/web3.js";

const vectors = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
const log = readFileSync(process.argv[2], "utf8");
const parse = (label) => Transaction.from(Buffer.from(log.match(new RegExp(`^${label} ([0-9a-f]+)$`, "m"))[1], "hex"));
const describe = (transaction) => JSON.stringify(transaction.instructions.map((instruction) => ({
  program: instruction.programId.toBase58(),
  keys: instruction.keys.map((key) => ({ pubkey: key.pubkey.toBase58(), signer: key.isSigner, writable: key.isWritable })),
  data: Buffer.from(instruction.data).toString("hex"),
})));
const check = (condition, label) => { if (!condition) { console.error(`FAIL ${label}`); process.exitCode = 1; } };

const ticket = parse("TICKET_TX");
check(ticket.feePayer.toBase58() === vectors.ticket.owner, "ticket fee payer");
check(describe(ticket) === JSON.stringify(vectors.ticket.instructions), "ticket instructions");
check(ticket.signatures.length === 2 && ticket.signatures[0].signature === null, "wallet signature slot is empty");
const mint = ticket.signatures[1];
check(mint.publicKey.toBase58() === vectors.ticket.mint && ed25519.verify(mint.signature, ticket.serializeMessage(), mint.publicKey.toBytes()), "mint signature");

const checkIn = parse("CHECKIN_TX");
check(checkIn.feePayer.toBase58() === vectors.checkIn.organizer, "check-in fee payer");
check(describe(checkIn) === JSON.stringify(vectors.checkIn.instructions), "check-in instructions");
if (!process.exitCode) console.log("OK web3.js parses both transactions identically");
