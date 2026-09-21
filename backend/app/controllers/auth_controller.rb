class AuthController < ApplicationController
  before_action :authenticate!, only: :me

  def register
    user = User.new(name: params.require(:name).to_s.strip, email: params.require(:email).to_s.downcase.strip)
    password = params.require(:password).to_s
    return render json: { detail: "password is too short" }, status: :unprocessable_entity if password.length < 6

    user.password = password
    user.save!
    render json: tokens(user), status: :created
  end

  def login
    user = User.find_by(email: params.require(:email).to_s.downcase.strip)
    return render json: { detail: "bad credentials" }, status: :unauthorized unless user&.authenticate(params.require(:password).to_s)

    render json: tokens(user)
  end

  def refresh
    raw = params[:refresh_token].presence
    return render json: { detail: "refresh token required" }, status: :unprocessable_entity unless raw

    payload = Auth::Token.decode(raw, type: "refresh")
    render json: tokens(User.find(payload.fetch("sub")))
  rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
    render json: { detail: "invalid refresh token" }, status: :unauthorized
  end

  def me
    render json: user_json(current_user) if current_user
  end

  private

  def tokens(user)
    {
      access_token: Auth::Token.issue(user),
      refresh_token: Auth::Token.issue(user, type: "refresh"),
      user: user_json(user)
    }
  end

  def user_json(user)
    user.as_json(only: %i[id name email role wallet_address wallet_verified_at])
  end
end
