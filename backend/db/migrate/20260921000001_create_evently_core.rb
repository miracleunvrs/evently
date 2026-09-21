class CreateEventlyCore < ActiveRecord::Migration[8.1]
  def change
    create_table :users, if_not_exists: true do |t|
      t.string :email, null: false
      t.string :name, null: false, default: ""
      t.string :role, null: false, default: "visitor"
      t.string :password_hash, null: false, default: ""
      t.string :wallet_address
      t.datetime :wallet_verified_at
      t.string :wallet_challenge_digest
      t.datetime :wallet_challenge_expires_at
      t.timestamps
    end

    create_table :categories, if_not_exists: true do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.timestamps
    end

    create_table :events, if_not_exists: true do |t|
      t.references :organizer, null: false, foreign_key: { to_table: :users }
      t.references :category, foreign_key: true
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.string :city, null: false, default: ""
      t.string :place, null: false, default: ""
      t.string :starts_at, null: false, default: ""
      t.integer :capacity, null: false, default: 100
      t.integer :price, null: false, default: 0
      t.string :status, null: false, default: "published"
      t.text :cover_url, null: false, default: ""
      t.timestamps
    end

    create_table :registrations, if_not_exists: true do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "confirmed"
      t.timestamps
    end

    create_table :tickets, if_not_exists: true do |t|
      t.references :registration, null: false, foreign_key: true
      t.string :code, null: false
      t.string :status, null: false, default: "active"
      t.string :wallet_address, limit: 44
      t.string :solana_signature, limit: 128
      t.string :token_address, limit: 44
      t.string :blockchain_status, null: false, default: "pending"
      t.text :blockchain_error
      t.string :check_in_signature, limit: 128
      t.datetime :checked_in_at
      t.timestamps
    end

    create_table :favorites, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.timestamps
    end

    create_table :check_ins, if_not_exists: true do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.references :checked_by, foreign_key: { to_table: :users }
      t.string :result, null: false, default: "ok"
      t.timestamps
    end

    add_column :users, :wallet_address, :string, limit: 44 unless column_exists?(:users, :wallet_address)
    add_column :users, :wallet_verified_at, :datetime unless column_exists?(:users, :wallet_verified_at)
    add_column :users, :wallet_challenge_digest, :string unless column_exists?(:users, :wallet_challenge_digest)
    add_column :users, :wallet_challenge_expires_at, :datetime unless column_exists?(:users, :wallet_challenge_expires_at)
    add_column :tickets, :wallet_address, :string, limit: 44 unless column_exists?(:tickets, :wallet_address)
    add_column :tickets, :solana_signature, :string, limit: 128 unless column_exists?(:tickets, :solana_signature)
    add_column :tickets, :token_address, :string, limit: 44 unless column_exists?(:tickets, :token_address)
    add_column :tickets, :blockchain_status, :string, null: false, default: "pending" unless column_exists?(:tickets, :blockchain_status)
    add_column :tickets, :blockchain_error, :text unless column_exists?(:tickets, :blockchain_error)
    add_column :tickets, :check_in_signature, :string, limit: 128 unless column_exists?(:tickets, :check_in_signature)
    add_column :tickets, :checked_in_at, :datetime unless column_exists?(:tickets, :checked_in_at)

    add_index :users, :email, unique: true, if_not_exists: true
    add_index :users, :wallet_address, unique: true, where: "wallet_address IS NOT NULL", if_not_exists: true
    add_index :categories, :slug, unique: true, if_not_exists: true
    add_index :categories, :title, unique: true, if_not_exists: true
    add_index :registrations, %i[event_id user_id], unique: true, if_not_exists: true
    add_index :registrations, %i[event_id status created_at], if_not_exists: true
    add_index :tickets, :registration_id, unique: true, if_not_exists: true
    add_index :tickets, :code, unique: true, if_not_exists: true
    add_index :tickets, :solana_signature, unique: true, where: "solana_signature IS NOT NULL", if_not_exists: true
    add_index :tickets, :token_address, unique: true, where: "token_address IS NOT NULL", if_not_exists: true
    add_index :tickets, %i[wallet_address blockchain_status], if_not_exists: true
    add_index :favorites, %i[user_id event_id], unique: true, if_not_exists: true
  end
end
