require "test_helper"

class EventCoverTest < ActiveSupport::TestCase
  setup do
    @organizer = User.create!(name: "Organizer", email: "covers-#{SecureRandom.hex(5)}@example.test", role: "organizer", password: "password123")
  end

  test "new event receives a cover from the shared collection" do
    event = Event.create!(organizer: @organizer, title: "Cover test", capacity: 20)

    assert_includes Event::COVER_URLS, event.cover_url
    assert_equal event.cover_url, event.reload.cover_url
  end

  test "chosen cover is not replaced" do
    event = Event.create!(organizer: @organizer, title: "Custom cover", capacity: 20, cover_url: "/my-cover.jpg")

    assert_equal "/my-cover.jpg", event.cover_url
  end
end
