categories = {
  "design" => "Дизайн",
  "tech" => "Технологии",
  "networking" => "Нетворкинг",
  "music" => "Музыка",
  "science" => "Наука"
}
categories.each { |slug, title| Category.find_or_create_by!(slug: slug) { |row| row.title = title } }

organizer = User.find_or_initialize_by(email: "orga@example.com")
organizer.assign_attributes(name: "Организатор", role: "organizer")
organizer.password = "orga123" if organizer.password_hash.blank?
organizer.save!

[
  [ "Future of Work / Almaty", "tech", "Алматы", "Terrenkur Hall", 5, "18:30", 240 ],
  [ "After Hours: Product People", "networking", "Астана", "Rooftop 18", 8, "20:00", 90 ],
  [ "Design Systems Picnic", "design", "Алматы", "Ботанический сад", 15, "12:00", 320 ]
].each do |title, slug, city, place, offset, time, capacity|
  Event.find_or_create_by!(title: title) do |event|
    event.organizer = organizer
    event.category = Category.find_by!(slug: slug)
    event.description = "Демо-событие Evently Web3."
    event.city = city
    event.place = place
    event.starts_at = (Time.current + offset.days).strftime("%Y-%m-%dT#{time}:00")
    event.capacity = capacity
    event.status = "published"
  end
end
