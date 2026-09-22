raise "Demo accounts are for local development only" unless Rails.env.development?

accounts = [
  { email: "client@evently.test", name: "Тестовый посетитель", role: "visitor" },
  { email: "orga@example.com", name: "Тестовый организатор", role: "organizer" },
  { email: "admin@evently.test", name: "Тестовый администратор", role: "admin" }
]

credentials = accounts.map do |attributes|
  password = "#{SecureRandom.urlsafe_base64(20)}aA1!"
  user = User.find_or_initialize_by(email: attributes[:email])
  user.assign_attributes(attributes)
  user.password = password
  user.save!
  "#{attributes[:role]}\t#{attributes[:email]}\t#{password}"
end

path = Rails.root.join("tmp", "demo_accounts.txt")
File.write(path, credentials.join("\n") + "\n", mode: "w", perm: 0o600)
File.chmod(0o600, path)
puts "Local demo credentials saved to #{path}"
