class AddUniqueCheckInSignatureIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :tickets, :check_in_signature,
      unique: true,
      where: "check_in_signature IS NOT NULL",
      if_not_exists: true
  end
end
