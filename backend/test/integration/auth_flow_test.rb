require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  test "accepts JSON registration and authenticates the created user" do
    email = "integration-#{SecureRandom.hex(6)}@example.com"

    post "/auth/register",
      params: { name: "Integration Guest", email: email, password: "secret123", password_confirmation: "secret123" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    body = response.parsed_body
    assert_equal email, body.dig("user", "email")
    assert body["access_token"].present?

    get "/auth/me", headers: { "Authorization" => "Bearer #{body.fetch("access_token")}" }

    assert_response :success
    assert_equal email, response.parsed_body["email"]
  end

  test "rejects mismatched passwords without creating an account" do
    email = "mismatch-#{SecureRandom.hex(6)}@example.com"

    post "/auth/register",
      params: { name: "Integration Guest", email: email, password: "secret123", password_confirmation: "different" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal "password_mismatch", response.parsed_body["code"]
    assert_not User.exists?(email: email)
  end

  test "rejects duplicate email regardless of case" do
    email = "duplicate-#{SecureRandom.hex(6)}@example.com"
    User.create!(name: "First Guest", email: email, password: "secret123")

    post "/auth/register",
      params: { name: "Second Guest", email: email.upcase, password: "secret123", password_confirmation: "secret123" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :conflict
    assert_equal "email_taken", response.parsed_body["code"]
  end
end
