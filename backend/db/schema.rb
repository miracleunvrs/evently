# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alembic_version", primary_key: "version_num", id: { type: :string, limit: 32 }, force: :cascade do |t|
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
    t.index ["title"], name: "index_categories_on_title", unique: true
  end

  create_table "check_ins", force: :cascade do |t|
    t.bigint "checked_by_id"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "result", default: "ok", null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_by_id"], name: "index_check_ins_on_checked_by_id"
    t.index ["event_id"], name: "index_check_ins_on_event_id"
    t.index ["ticket_id"], name: "index_check_ins_on_ticket_id"
  end

  create_table "event_images", id: :serial, force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "sort", null: false
    t.string "url", limit: 512, null: false
    t.index ["event_id"], name: "ix_event_images_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "capacity", default: 100, null: false
    t.bigint "category_id"
    t.string "city", default: "", null: false
    t.text "cover_url", default: "", null: false
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.bigint "organizer_id", null: false
    t.string "place", default: "", null: false
    t.integer "price", default: 0, null: false
    t.string "starts_at", default: "", null: false
    t.string "status", default: "published", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_events_on_category_id"
    t.index ["organizer_id"], name: "index_events_on_organizer_id"
  end

  create_table "favorites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_favorites_on_event_id"
    t.index ["user_id", "event_id"], name: "index_favorites_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_favorites_on_user_id"
  end

  create_table "refresh_tokens", id: :serial, force: :cascade do |t|
    t.timestamptz "created_at", default: -> { "now()" }, null: false
    t.timestamptz "expires_at", null: false
    t.string "jti", limit: 64, null: false
    t.boolean "revoked", null: false
    t.integer "user_id", null: false
    t.index ["jti"], name: "ix_refresh_tokens_jti", unique: true
    t.index ["user_id"], name: "ix_refresh_tokens_user_id"
  end

  create_table "registrations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "status", default: "confirmed", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id", "status", "created_at"], name: "index_registrations_on_event_id_and_status_and_created_at"
    t.index ["event_id", "user_id"], name: "index_registrations_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_registrations_on_event_id"
    t.index ["user_id"], name: "index_registrations_on_user_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.text "blockchain_error"
    t.string "blockchain_status", default: "pending", null: false
    t.string "check_in_signature", limit: 128
    t.datetime "checked_in_at"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "registration_id", null: false
    t.string "solana_signature", limit: 128
    t.string "status", default: "active", null: false
    t.string "token_address", limit: 44
    t.datetime "updated_at", null: false
    t.string "wallet_address", limit: 44
    t.index ["check_in_signature"], name: "index_tickets_on_check_in_signature", unique: true, where: "(check_in_signature IS NOT NULL)"
    t.index ["code"], name: "index_tickets_on_code", unique: true
    t.index ["registration_id"], name: "index_tickets_on_registration_id", unique: true
    t.index ["solana_signature"], name: "index_tickets_on_solana_signature", unique: true, where: "(solana_signature IS NOT NULL)"
    t.index ["token_address"], name: "index_tickets_on_token_address", unique: true, where: "(token_address IS NOT NULL)"
    t.index ["wallet_address", "blockchain_status"], name: "index_tickets_on_wallet_address_and_blockchain_status"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", default: "", null: false
    t.string "password_hash", default: "", null: false
    t.string "role", default: "visitor", null: false
    t.datetime "updated_at", null: false
    t.string "wallet_address"
    t.string "wallet_challenge_digest"
    t.datetime "wallet_challenge_expires_at"
    t.datetime "wallet_verified_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["wallet_address"], name: "index_users_on_wallet_address", unique: true, where: "(wallet_address IS NOT NULL)"
  end

  add_foreign_key "check_ins", "events"
  add_foreign_key "check_ins", "tickets"
  add_foreign_key "check_ins", "users", column: "checked_by_id"
  add_foreign_key "events", "categories"
  add_foreign_key "events", "users", column: "organizer_id"
  add_foreign_key "favorites", "events"
  add_foreign_key "favorites", "users"
  add_foreign_key "registrations", "events"
  add_foreign_key "registrations", "users"
  add_foreign_key "tickets", "registrations"
end
