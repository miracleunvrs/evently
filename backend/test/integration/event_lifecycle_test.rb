require "test_helper"

class EventLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @owner = user("organizer")
    @guest = user("visitor")
    @event = Event.create!(organizer: @owner, title: "Lifecycle", starts_at: 2.days.from_now.iso8601, capacity: 1)
  end

  test "management list includes own hidden events but never another organizers events" do
    @event.update!(status: "hidden")
    other = Event.create!(organizer: user("organizer"), title: "Other", starts_at: 2.days.from_now.iso8601)
    get "/me/events", headers: headers(@owner)
    assert_response :success
    assert_equal [ @event.id ], response.parsed_body.map { |row| row["id"] }
    get "/events"
    assert_equal [ other.id ], response.parsed_body.map { |row| row["id"] }
    get "/me/events", headers: headers(@guest)
    assert_response :forbidden
  end

  test "hidden and past events reject waitlist entries" do
    @event.registrations.create!(user: user("visitor"), status: "confirmed")
    @event.update!(status: "hidden")
    post "/events/#{@event.id}/waitlist", headers: headers(@guest)
    assert_response :not_found
    @event.update!(status: "published", starts_at: 1.day.ago.iso8601)
    post "/events/#{@event.id}/waitlist", headers: headers(@guest)
    assert_response :conflict
    assert_not @guest.registrations.exists?
  end

  test "capacity cannot be reduced below registrations" do
    @event.update!(capacity: 2)
    2.times { @event.registrations.create!(user: user("visitor")) }
    patch "/events/#{@event.id}", params: { capacity: 1 }, headers: headers(@owner), as: :json
    assert_response :unprocessable_entity
    assert_equal 2, @event.reload.capacity
  end

  test "event creation rejects an unparseable date" do
    post "/events", params: { title: "Bad date", starts_at: "12 октября · 19:00" }, headers: headers(@owner), as: :json
    assert_response :unprocessable_entity
  end

  test "used tickets cannot be canceled or reconfirmed" do
    ticket = @event.registrations.create!(user: @guest).create_ticket!(code: "USED", status: "used", blockchain_status: "used")
    delete "/registrations/#{ticket.registration_id}", headers: headers(@guest)
    assert_response :conflict
    post "/tickets/#{ticket.id}/blockchain", params: { solana_signature: "2" * 88, token_address: "3" * 44 }, headers: headers(@guest), as: :json
    assert_response :conflict
    assert_equal "used", ticket.reload.blockchain_status
  end

  test "cancellation promotes exactly one waiting guest" do
    ticket = @event.registrations.create!(user: @guest).create_ticket!(code: "CANCEL")
    waiting = @event.registrations.create!(user: user("visitor"), status: "waitlisted")
    delete "/registrations/#{ticket.registration_id}", headers: headers(@guest)
    assert_response :no_content
    assert_equal "confirmed", waiting.reload.status
    assert_equal "pending", waiting.ticket.blockchain_status
    assert_equal 1, @event.occupied
  end

  test "personal tickets retain event details after it is hidden" do
    @event.registrations.create!(user: @guest).create_ticket!(code: "HIDDEN")
    @event.update!(status: "hidden")
    get "/me/tickets", headers: headers(@guest)
    assert_response :success
    assert_equal @event.id, response.parsed_body.first.dig("event", "id")
  end

  test "registration respects capacity and rejects past events" do
    @guest.update!(wallet_address: "2" * 44, wallet_verified_at: Time.current)
    @event.registrations.create!(user: user("visitor"))
    post "/events/#{@event.id}/register", headers: headers(@guest)
    assert_response :conflict
    @event.update!(capacity: 2, starts_at: 1.day.ago.iso8601)
    post "/events/#{@event.id}/register", headers: headers(@guest)
    assert_response :conflict
    assert_not @guest.registrations.exists?
  end

  test "another organizer cannot update or read guests" do
    outsider = user("organizer")
    patch "/events/#{@event.id}", params: { title: "Hijacked" }, headers: headers(outsider), as: :json
    assert_response :forbidden
    get "/events/#{@event.id}/guests", headers: headers(outsider)
    assert_response :not_found
    assert_equal "Lifecycle", @event.reload.title
  end

  test "failed reconfirmation cannot downgrade a confirmed ticket" do
    ticket = @event.registrations.create!(user: @guest).create_ticket!(code: "CONFIRMED", blockchain_status: "confirmed", solana_signature: "2" * 88, token_address: "3" * 44)
    post "/tickets/#{ticket.id}/blockchain", params: { solana_signature: "4" * 88, token_address: "5" * 44 }, headers: headers(@guest), as: :json
    assert_response :conflict
    assert_equal "confirmed", ticket.reload.blockchain_status
    post "/tickets/#{ticket.id}/blockchain", params: { solana_signature: ticket.solana_signature, token_address: ticket.token_address }, headers: headers(@guest), as: :json
    assert_response :success
  end

  private

  def user(role)
    User.create!(name: "Test User", email: "#{SecureRandom.hex(8)}@example.test", password: "password123", role: role)
  end

  def headers(user)
    { "Authorization" => "Bearer #{Auth::Token.issue(user)}" }
  end
end
