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
if organizer.new_record? || (Rails.env.production? && organizer.authenticate("orga123"))
  organizer.password = ENV.fetch("EVENTLY_SEED_ORGANIZER_PASSWORD") { SecureRandom.urlsafe_base64(32) }
end
organizer.save!

events = [
  {
    title: "Future of Work / Almaty", category: "tech", city: "Алматы", place: "Terrenkur Hall",
    offset: 5, time: "18:30", capacity: 240, cover: "/covers/01-future-work.jpg",
    description: "Идеи, люди и технологии, которые меняют работу. Короткие выступления и живые дискуссии."
  },
  {
    title: "After Hours: Product People", category: "networking", city: "Астана", place: "Rooftop 18",
    offset: 8, time: "20:00", capacity: 90, cover: "/covers/02-after-dark.jpg",
    description: "Вечер для продуктовых команд: разговоры без слайдов, новые знакомства и город после заката."
  },
  {
    title: "Design Systems Picnic", category: "design", city: "Алматы", place: "Ботанический сад",
    offset: 15, time: "12:00", capacity: 320, cover: "/covers/03-creative-play.jpg",
    description: "Дизайн-системы за пределами переговорной: обмен практиками и идеи на свежем воздухе."
  },
  {
    title: "Soft Signals: Design Night", category: "design", city: "Алматы", place: "Aspan Gallery",
    offset: 14, time: "19:00", capacity: 160, cover: "/covers/03-creative-play.jpg",
    description: "Визуальные эксперименты, независимые студии и новые формы цифрового дизайна."
  },
  {
    title: "Night Shift: Electronic Sessions", category: "music", city: "Астана", place: "Plasma Hall",
    offset: 18, time: "21:00", capacity: 280, cover: "/covers/02-after-dark.jpg",
    description: "Ночь электронной музыки, световых инсталляций и неожиданных коллабораций."
  },
  {
    title: "Tomorrow Lab / Almaty", category: "science", city: "Алматы", place: "Tech Garden",
    offset: 22, time: "17:30", capacity: 180, cover: "/covers/01-future-work.jpg",
    description: "Открытая лаборатория идей на стыке науки, городов и новых технологий."
  },
  {
    title: "City Makers Meetup", category: "networking", city: "Шымкент", place: "Creative Hub",
    offset: 27, time: "18:00", capacity: 120, cover: "/covers/03-creative-play.jpg",
    description: "Городские проекты и люди, которые делают общественные пространства живыми."
  },
  {
    title: "New Forms Festival", category: "design", city: "Астана", place: "Art Station",
    offset: 33, time: "15:00", capacity: 400, cover: "/covers/02-after-dark.jpg",
    description: "Фестиваль молодого дизайна, музыки и инсталляций на целый день."
  }
]

events.each do |item|
  event = Event.find_or_create_by!(title: item[:title]) do |row|
    row.organizer = organizer
    row.category = Category.find_by!(slug: item[:category])
    row.description = item[:description]
    row.city = item[:city]
    row.place = item[:place]
    row.starts_at = (Time.current + item[:offset].days).strftime("%Y-%m-%dT#{item[:time]}:00")
    row.capacity = item[:capacity]
    row.cover_url = item[:cover]
    row.status = "published"
  end
  event.update!(cover_url: item[:cover]) if event.cover_url.blank?
end
