class AuthController < ApplicationController
  before_action :authenticate!, only: :me

  def register
    name = params.require(:name).to_s.squish
    email = params.require(:email).to_s.downcase.strip
    password = params.require(:password).to_s
    confirmation = params[:password_confirmation].to_s
    return registration_error("invalid_name", "Укажите имя от 2 до 80 символов") unless name.length.between?(2, 80)
    return registration_error("invalid_email", "Укажите корректный email") unless email.length <= 254 && email.match?(URI::MailTo::EMAIL_REGEXP)
    return registration_error("weak_password", "Пароль должен содержать не менее 8 символов") if password.length < 8
    return registration_error("password_too_long", "Пароль слишком длинный") if password.bytesize > 72
    return registration_error("password_mismatch", "Пароли не совпадают") unless password == confirmation
    return render json: { code: "email_taken", detail: "Этот email уже зарегистрирован" }, status: :conflict if User.exists?(email: email)

    user = User.new(name: name, email: email)
    user.password = password
    user.save!
    render json: tokens(user), status: :created
  rescue ActiveRecord::RecordNotUnique
    render json: { code: "email_taken", detail: "Этот email уже зарегистрирован" }, status: :conflict
  end

  def login
    user = User.find_by(email: params.require(:email).to_s.downcase.strip)
    return render json: { code: "invalid_credentials", detail: "Неверный email или пароль" }, status: :unauthorized unless user&.authenticate(params.require(:password).to_s)

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

  def registration_error(code, detail)
    render json: { code: code, detail: detail }, status: :unprocessable_entity
  end

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
