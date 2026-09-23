class EnsureOneTicketPerRegistration < ActiveRecord::Migration[8.1]
  def change
    remove_index :tickets, :registration_id
    add_index :tickets, :registration_id, unique: true
  end
end
