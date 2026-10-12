require "test_helper"

class GoogleAuthTest < ActionDispatch::IntegrationTest
  CLIENT_ID = "123-test.apps.googleusercontent.com".freeze

  setup do
    @key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@key, kid: "test-key")
    jwks = JWT::JWK::Set.new(@jwk)
    @original_certs = Auth::GoogleIdToken.method(:certs)
    Auth::GoogleIdToken.define_singleton_method(:certs) { |force: false| jwks }
    @original_client_ids = ENV["GOOGLE_CLIENT_IDS"]
    ENV["GOOGLE_CLIENT_IDS"] = CLIENT_ID
    @email = "google-#{SecureRandom.hex(6)}@example.com"
    @sub = SecureRandom.random_number(10**21).to_s
  end

  teardown do
    Auth::GoogleIdToken.define_singleton_method(:certs, @original_certs)
    ENV["GOOGLE_CLIENT_IDS"] = @original_client_ids
  end

  test "creates a visitor account from a valid Google token and signs it in" do
    sign_in id_token
    assert_response :created
    body = response.parsed_body
    assert_equal @email, body.dig("user", "email")
    assert_equal "Google Guest", body.dig("user", "name")
    assert_equal "visitor", body.dig("user", "role")

    get "/auth/me", headers: { "Authorization" => "Bearer #{body.fetch("access_token")}" }
    assert_response :success
    assert_equal @email, response.parsed_body["email"]
  end

  test "returns the same account on the next sign-in even after the Google email changes" do
    sign_in id_token
    first = response.parsed_body.dig("user", "id")
    sign_in id_token({ "email" => "renamed-#{@email}" })
    assert_response :success
    assert_equal first, response.parsed_body.dig("user", "id")
    assert_equal 1, User.where(google_sub: @sub).count
  end

  test "links Google to an existing password account with the same verified email" do
    existing = User.create!(name: "Password Guest", email: @email, password: "secret123", role: "organizer")
    sign_in id_token({ "email" => @email.upcase })
    assert_response :success
    assert_equal existing.id, response.parsed_body.dig("user", "id")
    assert_equal "organizer", response.parsed_body.dig("user", "role")
    assert_equal @sub, existing.reload.google_sub
    assert existing.authenticate("secret123")
  end

  test "Google-only account cannot be opened with a password" do
    sign_in id_token
    post "/auth/login", params: { email: @email, password: "anything1" }.to_json, headers: json
    assert_response :unauthorized
  end

  test "rejects tokens for another app, unverified emails, expired and forged tokens" do
    sign_in id_token({ "aud" => "999-other.apps.googleusercontent.com" })
    assert_response :unauthorized
    sign_in id_token({ "email_verified" => false })
    assert_response :unauthorized
    sign_in id_token({ "exp" => 1.minute.ago.to_i })
    assert_response :unauthorized
    sign_in id_token({ "iss" => "https://evil.example.com" })
    assert_response :unauthorized
    sign_in id_token({}, key: OpenSSL::PKey::RSA.generate(2048))
    assert_response :unauthorized
    sign_in JWT.encode(claims.merge("exp" => 5.minutes.from_now.to_i), nil, "none")
    assert_response :unauthorized
    assert_equal "invalid_google_token", response.parsed_body["code"]
    assert_not User.exists?(email: @email)
  end

  test "reports when Google sign-in is not configured" do
    ENV["GOOGLE_CLIENT_IDS"] = ""
    sign_in id_token
    assert_response :service_unavailable
    assert_equal "google_not_configured", response.parsed_body["code"]
  end

  private

  def json = { "Content-Type" => "application/json" }

  def sign_in(token)
    post "/auth/google", params: { id_token: token }.to_json, headers: json
  end

  def claims
    { "iss" => "https://accounts.google.com", "aud" => CLIENT_ID, "sub" => @sub, "email" => @email,
      "email_verified" => true, "name" => "Google Guest", "iat" => Time.current.to_i }
  end

  def id_token(overrides = {}, key: @key)
    JWT.encode(claims.merge("exp" => 5.minutes.from_now.to_i).merge(overrides), key, "RS256", kid: @jwk.kid)
  end
end
