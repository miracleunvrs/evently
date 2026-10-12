import SwiftUI
import CoreImage.CIFilterBuiltins

private struct Cover: View {
    let event: Event
    let height: CGFloat
    var body: some View {
        Image(event.coverName).resizable().scaledToFill()
            .frame(height: height).frame(maxWidth: .infinity).clipped()
    }
}

private struct EventCard: View {
    let event: Event
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Cover(event: event, height: 180)
                .overlay(alignment: .topTrailing) {
                    if event.ended {
                        Text("Завершено").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(.white).background(.black.opacity(0.65), in: Capsule()).padding(12)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                Text((event.category ?? "Событие").uppercased())
                    .font(.caption.bold()).tracking(1).foregroundStyle(Palette.accent)
                Text(event.title).font(.title3.bold())
                Label(event.dateLabel, systemImage: "calendar")
                Label("\(event.city) · \(event.place)", systemImage: "mappin")
            }.font(.subheadline).padding(16)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var api: EventlyAPI
    @State private var search = ""
    @State private var city = "Все"
    private var cities: [String] { ["Все"] + Array(Set(api.events.map(\.city))).sorted() }
    private var filtered: [Event] {
        api.events.filter {
            (city == "Все" || $0.city == city) &&
            (search.isEmpty || "\($0.title) \($0.city) \($0.place) \($0.category ?? "")"
                .localizedCaseInsensitiveContains(search))
        }
    }
    private var upcoming: [Event] {
        filtered.filter { !$0.ended }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var past: [Event] {
        filtered.filter(\.ended).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("EVENTLY / АФИША").font(.caption.bold()).tracking(2).foregroundStyle(Palette.accent)
                Text("Моменты, ради которых выходят из дома.")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                HStack { Image(systemName: "magnifyingglass"); TextField("Событие, город, место", text: $search) }
                    .padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(cities, id: \.self) { item in
                            Button(item) { city = item }
                                .font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 9)
                                .background(city == item ? Palette.ink : Palette.card, in: Capsule())
                                .foregroundStyle(city == item ? Palette.onInk : Palette.ink)
                        }
                    }
                }
                HStack { Text("Ближайшие события").font(.title2.bold()); Spacer(); Text("\(upcoming.count)") }
                if api.loading && api.events.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if let error = api.error, api.events.isEmpty {
                    ContentUnavailableView("Не удалось загрузить", systemImage: "wifi.exclamationmark", description: Text(error))
                    Button("Повторить") { Task { await api.refresh() } }
                }
                ForEach(upcoming) { event in
                    NavigationLink { EventDetailView(event: event) } label: { EventCard(event: event) }.buttonStyle(.plain)
                }
                if upcoming.isEmpty && !api.loading && api.error == nil {
                    if filtered.isEmpty && !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView("Пока ничего не запланировано", systemImage: "calendar",
                                               description: Text("Новые события появятся здесь."))
                    }
                }
                if !past.isEmpty {
                    Text("Прошедшие").font(.title2.bold()).padding(.top, 8)
                    ForEach(past) { event in
                        NavigationLink { EventDetailView(event: event) } label: { EventCard(event: event) }.buttonStyle(.plain)
                    }
                }
            }.padding(18)
        }
        .background(Palette.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("evently.").font(.headline).foregroundStyle(Palette.accent) } }
        .refreshable { await api.refresh() }
    }
}

struct EventDetailView: View {
    @EnvironmentObject private var api: EventlyAPI
    @EnvironmentObject private var wallet: WalletCoordinator
    @Environment(\.openAuth) private var openAuth
    let event: Event
    @State private var message: String?
    @State private var busy = false
    /// The catalogue reloads after a registration; the copy this screen was pushed with would keep the old seat count.
    private var current: Event { api.events.first { $0.id == event.id } ?? event }
    private var ticket: Ticket? { api.tickets.first { $0.eventId == event.id } }
    private var waitlisted: WaitlistEntry? { api.waitlist.first { $0.eventId == event.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cover(event: current, height: 280)
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text((current.category ?? "Событие").uppercased()).font(.caption.bold()).foregroundStyle(Palette.accent)
                        Spacer()
                        Button {
                            if api.user == nil { openAuth(); return }
                            Task {
                                do { try await api.toggleFavorite(current) }
                                catch { message = error.localizedDescription }
                            }
                        } label: {
                            Image(systemName: api.favorites.contains(current.id) ? "heart.fill" : "heart")
                                .font(.title2).foregroundStyle(Palette.accent)
                        }.accessibilityLabel("Избранное")
                    }
                    Text(current.title).font(.system(size: 36, weight: .black, design: .rounded))
                    Text(current.description).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(current.dateLabel, systemImage: "calendar")
                        Label("\(current.place), \(current.city)", systemImage: "mappin.and.ellipse")
                        Label(current.price == 0 ? "Вход бесплатный" : "\(current.price) ₸", systemImage: "ticket")
                        Label(current.available > 0 ? "Осталось мест: \(current.available)" : "Мест нет", systemImage: "person.2")
                    }.font(.subheadline).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    action
                }.padding(.horizontal, 18)
            }.padding(.bottom, 30)
        }
        .background(Palette.paper).ignoresSafeArea(edges: .top)
        .alert("Evently", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Понятно", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    @ViewBuilder private var action: some View {
        if let ticket {
            if ticket.needsMint {
                note("Место за тобой", "Осталось выпустить билет в Solana: подпиши транзакцию в Phantom.")
                Button("Выпустить билет") { wallet.issueTicket(eventId: current.id) }.buttonStyle(PrimaryButtonStyle())
            } else {
                NavigationLink { TicketDetailView(ticket: ticket) } label: { Label("Открыть билет", systemImage: "ticket") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else if current.ended {
            Text("Событие завершилось").foregroundStyle(.secondary)
        } else if let waitlisted {
            note("Ты в листе ожидания", "Твой номер — \(waitlisted.position). Когда место освободится, билет появится во вкладке «Билеты».")
        } else if current.available == 0 {
            Button(busy ? "Добавляем…" : "В лист ожидания") {
                if api.user == nil { openAuth(); return }
                busy = true
                Task {
                    defer { busy = false }
                    do { try await api.joinWaitlist(current) }
                    catch { message = error.localizedDescription }
                }
            }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
        } else {
            Button("Получить билет") {
                if api.user == nil { openAuth() } else { wallet.issueTicket(eventId: current.id) }
            }.buttonStyle(PrimaryButtonStyle())
            Text("Билет — непередаваемый токен в Solana Devnet. Понадобится кошелёк Phantom и немного тестовых SOL.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.openAuth) private var openAuth
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if api.user == nil {
                    ContentUnavailableView("Сохраняй интересное", systemImage: "heart", description: Text("Войди, чтобы видеть избранное."))
                    Button("Войти", action: openAuth).buttonStyle(PrimaryButtonStyle())
                } else if api.favorites.isEmpty {
                    ContentUnavailableView("Пока пусто", systemImage: "heart", description: Text("Нажми на сердце в событии."))
                }
                ForEach(api.events.filter { api.favorites.contains($0.id) }) { event in
                    NavigationLink { EventDetailView(event: event) } label: { EventCard(event: event) }.buttonStyle(.plain)
                }
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Избранное").refreshable { await api.refreshPrivate() }
    }
}

private struct QRImage: View {
    let value: String
    var body: some View {
        if let image = makeImage() { Image(uiImage: image).interpolation(.none).resizable().scaledToFit() }
        else { Image(systemName: "qrcode") }
    }
    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(enlarged, from: enlarged.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct TicketsView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.openAuth) private var openAuth
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if api.user == nil {
                    ContentUnavailableView("Твои билеты здесь", systemImage: "ticket", description: Text("Войди в аккаунт, чтобы открыть билеты."))
                    Button("Войти", action: openAuth).buttonStyle(PrimaryButtonStyle())
                } else if api.tickets.isEmpty && api.waitlist.isEmpty {
                    ContentUnavailableView("Билетов пока нет", systemImage: "ticket", description: Text("После оформления они появятся здесь."))
                }
                ForEach(api.tickets) { ticket in
                    NavigationLink { TicketDetailView(ticket: ticket) } label: {
                        HStack {
                            Image(systemName: "ticket.fill").font(.title2).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading) {
                                Text(ticket.eventTitle).font(.headline)
                                Text(ticket.needsMint ? "Ждёт выпуска в Solana" : ticket.event.dateLabel)
                                    .font(.caption).foregroundStyle(ticket.needsMint ? Palette.accent : .secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
                ForEach(api.waitlist) { item in
                    Label("\(item.eventTitle) · лист ожидания №\(item.position)", systemImage: "hourglass")
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Билеты").refreshable { await api.refreshPrivate() }
    }
}

struct TicketDetailView: View {
    @EnvironmentObject private var api: EventlyAPI
    @EnvironmentObject private var wallet: WalletCoordinator
    @Environment(\.dismiss) private var dismiss
    let ticket: Ticket
    @State private var confirming = false
    @State private var error: String?
    /// Minting changes the ticket while this screen is open.
    private var current: Ticket { api.tickets.first { $0.id == ticket.id } ?? ticket }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Cover(event: current.event, height: 180)
                VStack(spacing: 18) {
                    Text(current.eventTitle).font(.title.bold()).multilineTextAlignment(.center)
                    Text(current.event.dateLabel).foregroundStyle(.secondary)
                    if current.needsMint {
                        Label("Билет ещё не выпущен", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(current.blockchainStatus == "failed"
                             ? "Прошлая попытка не прошла проверку в Solana. Выпусти билет ещё раз."
                             : "Место за тобой. QR появится, когда билет будет выпущен в Solana.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Выпустить билет в Phantom") { wallet.issueTicket(eventId: current.eventId) }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        QRImage(value: current.code).frame(width: 220, height: 220)
                            .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .opacity(current.status == "used" ? 0.35 : 1)
                        Text(current.code).font(.system(.headline, design: .monospaced))
                        Text(current.status == "used" ? "Уже использован" : "Покажи QR на входе")
                        if let address = current.explorerUrl, let url = URL(string: address), url.scheme == "https" {
                            Link("Проверить в Solana Explorer", destination: url)
                        }
                    }
                    if current.status != "used" {
                        // On the button, so the confirmation points at it instead of floating at the top of the screen.
                        Button("Отменить регистрацию", role: .destructive) { confirming = true }
                            .confirmationDialog("Отменить регистрацию?", isPresented: $confirming, titleVisibility: .visible) {
                                Button("Отменить регистрацию", role: .destructive) {
                                    Task {
                                        do { try await api.cancel(current); dismiss() }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }
                                Button("Оставить билет", role: .cancel) {}
                            }
                    }
                }.padding(24).frame(maxWidth: .infinity)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 18)
            }
        }.background(Palette.paper).navigationTitle("Мой билет")
            .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.openAuth) private var openAuth
    @State private var settings = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let user = api.user {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 54)).foregroundStyle(Palette.accent)
                        Text(user.name).font(.title.bold())
                        Text(user.email).foregroundStyle(.secondary)
                        Text(user.role == "admin" ? "Администратор" : user.role == "organizer" ? "Организатор" : "Гость")
                            .font(.caption.bold())
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    WalletCard()
                    if user.managesEvents {
                        NavigationLink { OrganizerView() } label: { Label("Кабинет организатора", systemImage: "slider.horizontal.3") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if user.role == "admin" {
                        NavigationLink { AdminView() } label: { Label("Статистика платформы", systemImage: "chart.bar.xaxis") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Выйти", role: .destructive) { api.signOut() }
                        .frame(maxWidth: .infinity).padding(14)
                } else {
                    Text("Давай знакомиться.").font(.system(size: 36, weight: .black, design: .rounded))
                    Text("Войди, чтобы сохранять события и открывать билеты.").foregroundStyle(.secondary)
                    Button("Войти или зарегистрироваться", action: openAuth).buttonStyle(PrimaryButtonStyle())
                }
                Button("Адрес API", systemImage: "network") { settings = true }.foregroundStyle(.secondary)
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Профиль").sheet(isPresented: $settings) { APISettingsView() }
    }
}

private struct APISettingsView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("https://api.example.com", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Основной сервер уже настроен. Меняй адрес только для локальной разработки.")
                    .font(.footnote).foregroundStyle(.secondary)
                if invalid { Text("Укажи HTTPS-адрес или локальный HTTP-адрес.").foregroundStyle(.red) }
            }
            .navigationTitle("Подключение")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if api.updateAddress(address) { Task { await api.refresh() }; dismiss() }
                        else { invalid = true }
                    }
                }
            }
        }.onAppear { address = api.apiAddress }
    }
}

struct AuthView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.dismiss) private var dismiss
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var loading = false
    @State private var googling = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(registering ? "Начнём с тебя." : "С возвращением.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text(registering ? "Создай аккаунт и находи свои события." : "Войди в Evently, чтобы продолжить.")
                        .foregroundStyle(.secondary)
                    if registering { TextField("Имя", text: $name).textContentType(.name).textFieldStyle(.roundedBorder) }
                    TextField("Email", text: $email).textContentType(.emailAddress)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    SecureField("Пароль", text: $password).textFieldStyle(.roundedBorder)
                    if registering { SecureField("Повтори пароль", text: $confirmation).textFieldStyle(.roundedBorder) }
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                    Button(loading && !googling ? "Подожди…" : registering ? "Создать аккаунт" : "Войти") { submit() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(loading)
                    HStack(spacing: 12) {
                        Rectangle().frame(height: 1)
                        Text("или").font(.subheadline)
                        Rectangle().frame(height: 1)
                    }.foregroundStyle(.secondary.opacity(0.5))
                    Button { google() } label: {
                        HStack(spacing: 10) {
                            Image("GoogleLogo").resizable().frame(width: 20, height: 20)
                            Text(googling ? "Входим…" : "Продолжить с Google")
                        }
                    }.buttonStyle(OutlineButtonStyle()).disabled(loading)
                    Button(registering ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Зарегистрироваться") {
                        registering.toggle(); error = nil
                    }.frame(maxWidth: .infinity)
                }.padding(22)
            }.background(Palette.paper).navigationTitle("Evently")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
    private func submit() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEmail.isEmpty || password.isEmpty { error = "Укажи email и пароль"; return }
        if registering {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { error = "Имя слишком короткое"; return }
            if password.count < 8 { error = "Пароль должен содержать хотя бы 8 символов"; return }
            if password != confirmation { error = "Пароли не совпадают"; return }
        }
        loading = true; error = nil
        Task {
            defer { loading = false }
            do {
                if registering { try await api.register(name: name, email: cleanEmail, password: password) }
                else { try await api.login(email: cleanEmail, password: password) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func google() {
        loading = true; googling = true; error = nil
        Task {
            defer { loading = false; googling = false }
            do { if try await api.loginWithGoogle() { dismiss() } }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(16)
            .foregroundStyle(Palette.onInk).background(Palette.ink, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(16)
            .foregroundStyle(Palette.ink).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ink.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct OrganizerView: View {
    @EnvironmentObject private var api: EventlyAPI
    @State private var creating = false
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Button("Создать черновик", systemImage: "plus") { creating = true }.buttonStyle(PrimaryButtonStyle())
                NavigationLink { CheckInView() } label: { Label("Проверка билетов", systemImage: "qrcode.viewfinder") }
                    .buttonStyle(OutlineButtonStyle())
                ForEach(api.managed) { event in
                    NavigationLink { ManagedEventView(event: event) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.headline)
                                Text("\(event.statusLabel) · \(event.dateLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Мои события")
            .refreshable { await api.refreshPrivate() }.sheet(isPresented: $creating) { CreateEventView() }
    }
}

struct ManagedEventView: View {
    @EnvironmentObject private var api: EventlyAPI
    @EnvironmentObject private var wallet: WalletCoordinator
    let event: Event
    @State private var stats: EventStats?
    @State private var guests: [Guest] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Cover(event: event, height: 200)
                Text(event.title).font(.title.bold())
                if let stats {
                    HStack {
                        metric("Регистрации", stats.registrations)
                        metric("Посетили", stats.visits)
                        metric("Места", stats.capacity)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Text("Гости").font(.title2.bold())
                if guests.isEmpty && error == nil { Text("Пока никто не зарегистрировался").foregroundStyle(.secondary) }
                ForEach(guests) { guest in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(guest.name).font(.headline)
                            Text(guest.email).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let code = guest.code, guest.canCheckIn {
                            Button("Отметить") { wallet.checkIn(code: code) }.font(.subheadline.bold()).foregroundStyle(Palette.accent)
                        } else {
                            Text(guest.statusLabel).font(.caption)
                        }
                    }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Статистика")
            .task { await load() }.refreshable { await load() }
            .onChange(of: wallet.activity) { _, activity in
                // A check-in started from this list changes it.
                if case .success = activity?.phase { Task { await load() } }
            }
    }
    private func metric(_ title: String, _ value: Int) -> some View {
        VStack { Text("\(value)").font(.title.bold()); Text(title).font(.caption) }
            .frame(maxWidth: .infinity).padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
    }
    private func load() async {
        do { stats = try await api.stats(event); guests = try await api.guests(event); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CreateEventView: View {
    @EnvironmentObject private var api: EventlyAPI
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var city = ""
    @State private var place = ""
    @State private var startsAt = Date().addingTimeInterval(86400)
    @State private var capacity = 50
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Событие") {
                    TextField("Название", text: $title)
                    TextField("Описание", text: $description, axis: .vertical).lineLimit(3...6)
                    TextField("Город", text: $city)
                    TextField("Место", text: $place)
                }
                Section("Когда и сколько") {
                    DatePicker("Дата", selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Stepper("Мест: \(capacity)", value: $capacity, in: 1...5000)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Text("Создаётся черновик. Публикация и приглашения пока доступны в веб-кабинете.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Новый черновик")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loading ? "Сохраняем…" : "Сохранить") { save() }.disabled(loading)
                }
            }
        }
    }
    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Укажи название и город"; return
        }
        loading = true
        Task {
            defer { loading = false }
            do {
                try await api.createEvent(title: title, description: description, city: city,
                                          place: place, startsAt: startsAt, capacity: capacity)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct AdminView: View {
    @EnvironmentObject private var api: EventlyAPI
    @State private var overview: AdminOverview?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let overview {
                    metric("События", overview.events)
                    metric("Пользователи", overview.users)
                    metric("Регистрации", overview.registrations)
                    metric("Посещения", overview.visits)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding(18)
        }.background(Palette.paper).navigationTitle("Платформа")
            .task { await load() }.refreshable { await load() }
    }
    private func metric(_ title: String, _ value: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(value)").font(.title2.bold()) }
            .padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func load() async {
        do { overview = try await api.adminOverview(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
