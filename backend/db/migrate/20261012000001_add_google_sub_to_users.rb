class AddGoogleSubToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :google_sub, :string
    add_index :users, :google_sub, unique: true, where: "google_sub IS NOT NULL"
  end
end
