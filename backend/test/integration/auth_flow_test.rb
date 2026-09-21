require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  test "accepts JSON registration and authenticates the created user" do
    email = "integration-#{SecureRandom.hex(6)}@example.com"

    post "/auth/register",
      params: { name: "Integration Guest", email: email, password: "secret123" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    body = response.parsed_body
    assert_equal email, body.dig("user", "email")
    assert body["access_token"].present?

    get "/auth/me", headers: { "Authorization" => "Bearer #{body.fetch("access_token")}" }

    assert_response :success
    assert_equal email, response.parsed_body["email"]
  end
end
