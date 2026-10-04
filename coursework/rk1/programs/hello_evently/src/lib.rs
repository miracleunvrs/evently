#![allow(unexpected_cfgs)]
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint,
    entrypoint::ProgramResult,
    msg,
    program_error::ProgramError,
    pubkey::Pubkey,
};
entrypoint!(process_instruction);
pub fn process_instruction(
    _program_id: &Pubkey,
    accounts: &[AccountInfo],
    data: &[u8],
) -> ProgramResult {
    let signer = next_account_info(&mut accounts.iter())?;
    if !signer.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if data != b"evently-rk1" {
        return Err(ProgramError::InvalidInstructionData);
    }
    msg!("Hello Evently RK1");
    msg!("Signed by {}", signer.key);
    Ok(())
}
