class WalletsController < ApplicationController
  before_action :authenticate!

  def challenge
    return unless current_user
    wallet = params.require(:wallet_address).to_s
    return render json: { detail: "invalid Solana wallet" }, status: :unprocessable_entity unless wallet.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)

    nonce = SecureRandom.hex(24)
    message = "Evently wallet verification\nUser: #{current_user.id}\nWallet: #{wallet}\nNonce: #{nonce}"
    current_user.update!(wallet_challenge_digest: Digest::SHA256.hexdigest(message), wallet_challenge_expires_at: 10.minutes.from_now)
    render json: { message: message, expires_at: current_user.wallet_challenge_expires_at }
  end

  def verify
    return unless current_user
    wallet = params.require(:wallet_address).to_s
    message = params.require(:message).to_s
    signature = params.require(:signature).to_s

    valid_challenge = current_user.wallet_challenge_expires_at&.future? &&
      ActiveSupport::SecurityUtils.secure_compare(current_user.wallet_challenge_digest.to_s, Digest::SHA256.hexdigest(message)) &&
      message.include?("User: #{current_user.id}") && message.include?("Wallet: #{wallet}")
    valid_signature = valid_challenge && Solana::WalletSignature.valid?(wallet_address: wallet, message: message, signature: signature)
    return render json: { detail: "wallet signature is invalid" }, status: :unprocessable_entity unless valid_signature

    current_user.update!(wallet_address: wallet, wallet_verified_at: Time.current, wallet_challenge_digest: nil, wallet_challenge_expires_at: nil)
    render json: { wallet_address: wallet, verified: true }
  end
end
