#![allow(unexpected_cfgs)]
use anchor_lang::prelude::*;
declare_id!("DE89mDadLLX5WymVUu1giQZZXXKG72HVKzQVz7QPsSDc");

#[program]
pub mod evently_lab {
    use super::*;
    pub fn initialize_counter(ctx: Context<InitializeCounter>) -> Result<()> {
        let counter = &mut ctx.accounts.counter;
        counter.authority = ctx.accounts.authority.key();
        counter.count = 0;
        counter.bump = ctx.bumps.counter;
        Ok(())
    }
    pub fn increment(ctx: Context<Increment>) -> Result<()> {
        let counter = &mut ctx.accounts.counter;
        counter.count = counter.count.checked_add(1).ok_or(LabError::Overflow)?;
        Ok(())
    }
    pub fn create_profile(ctx: Context<CreateProfile>, name: String, bio: String) -> Result<()> {
        validate_profile(&name, &bio)?;
        let profile = &mut ctx.accounts.profile;
        profile.authority = ctx.accounts.authority.key();
        profile.name = name;
        profile.bio = bio;
        profile.bump = ctx.bumps.profile;
        Ok(())
    }
    pub fn update_profile(ctx: Context<UpdateProfile>, name: String, bio: String) -> Result<()> {
        validate_profile(&name, &bio)?;
        ctx.accounts.profile.name = name;
        ctx.accounts.profile.bio = bio;
        Ok(())
    }
}
fn validate_profile(name: &str, bio: &str) -> Result<()> {
    require!(
        !name.trim().is_empty() && name.len() <= 32,
        LabError::InvalidName
    );
    require!(bio.len() <= 160, LabError::InvalidBio);
    Ok(())
}
#[derive(Accounts)]
pub struct InitializeCounter<'info> {
    #[account(init, payer = authority, space = 8 + Counter::INIT_SPACE, seeds = [b"counter", authority.key().as_ref()], bump)]
    pub counter: Account<'info, Counter>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}
#[derive(Accounts)]
pub struct Increment<'info> {
    #[account(mut, seeds = [b"counter", authority.key().as_ref()], bump = counter.bump, has_one = authority)]
    pub counter: Account<'info, Counter>,
    pub authority: Signer<'info>,
}
#[derive(Accounts)]
pub struct CreateProfile<'info> {
    #[account(init, payer = authority, space = 8 + Profile::INIT_SPACE, seeds = [b"profile", authority.key().as_ref()], bump)]
    pub profile: Account<'info, Profile>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}
#[derive(Accounts)]
pub struct UpdateProfile<'info> {
    #[account(mut, seeds = [b"profile", authority.key().as_ref()], bump = profile.bump, has_one = authority)]
    pub profile: Account<'info, Profile>,
    pub authority: Signer<'info>,
}
#[account]
#[derive(InitSpace)]
pub struct Counter {
    pub authority: Pubkey,
    pub count: u64,
    pub bump: u8,
}
#[account]
#[derive(InitSpace)]
pub struct Profile {
    pub authority: Pubkey,
    #[max_len(32)]
    pub name: String,
    #[max_len(160)]
    pub bio: String,
    pub bump: u8,
}
#[error_code]
pub enum LabError {
    #[msg("Counter overflow")]
    Overflow,
    #[msg("Name must contain 1 to 32 UTF-8 bytes")]
    InvalidName,
    #[msg("Bio exceeds 160 UTF-8 bytes")]
    InvalidBio,
}
