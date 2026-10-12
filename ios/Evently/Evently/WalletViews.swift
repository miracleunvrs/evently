import SwiftUI
import VisionKit

func shortWallet(_ address: String) -> String { "\(address.prefix(4))…\(address.suffix(4))" }

/// Progress and outcome of the Phantom request in flight, shown over whatever screen started it.
struct WalletActivitySheet: View {
    @EnvironmentObject private var wallet: WalletCoordinator
    let activity: WalletActivity

    var body: some View {
        VStack(spacing: 18) {
            icon.font(.system(size: 46)).frame(height: 56)
            Text(activity.title).font(.title2.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            buttons
        }
        .padding(24).frame(maxWidth: .infinity)
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
    }

    private var busy: Bool {
        if case .progress = activity.phase { return true }
        return false
    }

    @ViewBuilder private var icon: some View {
        switch activity.phase {
        case .waiting: Image(systemName: "arrow.up.forward.app").foregroundStyle(Palette.accent)
        case .progress: ProgressView().controlSize(.large)
        case .confirmWallet: Image(systemName: "signature").foregroundStyle(Palette.accent)
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure, .devnetBlocked: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.accent)
        }
    }

    private var message: String {
        switch activity.phase {
        case .waiting: "Подтверди действие в приложении Phantom и вернись в Evently."
        case .progress(let text), .success(let text), .failure(let text): text
        case .confirmWallet(let address):
            "Кошелёк \(shortWallet(address)) подключён. Остался один шаг: подпиши сообщение, чтобы подтвердить, что он твой. Это бесплатно и ничего не списывает."
        case .devnetBlocked:
            "Phantom не выполнил запрос в сети Devnet. Обычно это значит, что в нём выключен Testnet Mode (Настройки → Developer Settings). Включи его и повтори — или продолжи без него: кошелёк подключится заново."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch activity.phase {
        case .waiting:
            Button("Открыть Phantom") { wallet.reopen() }.buttonStyle(PrimaryButtonStyle())
            Button("Отмена") { wallet.cancel() }
        case .progress:
            EmptyView()
        case .confirmWallet:
            Button("Подписать в Phantom") { wallet.confirmWallet() }.buttonStyle(PrimaryButtonStyle())
            Button("Позже") { wallet.cancel() }
        case .success:
            if let resume = wallet.resume {
                Button(resume.label) { wallet.continueAfterWallet() }.buttonStyle(PrimaryButtonStyle())
                Button("Позже") { wallet.cancel() }
            } else {
                Button("Готово") { wallet.cancel() }.buttonStyle(PrimaryButtonStyle())
            }
        case .failure:
            Button("Понятно") { wallet.cancel() }.buttonStyle(PrimaryButtonStyle())
        case .devnetBlocked:
            Button("Продолжить без Devnet") { wallet.continueWithoutDevnet() }.buttonStyle(PrimaryButtonStyle())
            Button("Отмена") { wallet.cancel() }
        }
    }
}

/// Wallet status on the profile screen.
struct WalletCard: View {
    @EnvironmentObject private var api: EventlyAPI
    @EnvironmentObject private var wallet: WalletCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Кошелёк Phantom", systemImage: "wallet.pass").font(.headline)
            if let address = api.user?.verifiedWallet {
                Text(shortWallet(address)).font(.system(.title3, design: .monospaced).bold())
                if wallet.isReady(for: api.user) {
                    Label("Подтверждён · Solana Devnet", systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Кошелёк привязан к аккаунту. Подключи Phantom на этом iPhone, чтобы получать билеты и отмечать гостей.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Подключить Phantom") { wallet.connect() }.buttonStyle(PrimaryButtonStyle())
                }
                Button("Сменить кошелёк") { wallet.connect() }.font(.subheadline)
            } else {
                Text("Билеты Evently — непередаваемые токены в Solana Devnet. Подключи Phantom, чтобы получать их и проходить на события.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Подключить Phantom") { wallet.setUp() }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// Door check for organizers: every pass is signed by the organizer's wallet on Solana.
struct CheckInView: View {
    @EnvironmentObject private var wallet: WalletCoordinator
    @State private var code = ""
    @State private var scanning = false
    @State private var scanned: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Отсканируй QR с билета гостя или введи код. Проход подтверждается подписью твоего кошелька в Solana Devnet, поэтому понадобится Phantom.")
                    .foregroundStyle(.secondary)
                TextField("Код билета: EVT-…", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                Button("Проверить билет") { wallet.checkIn(code: code) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if TicketScanner.isSupported {
                    Button { scanning = true } label: { Label("Сканировать QR", systemImage: "qrcode.viewfinder") }
                        .buttonStyle(OutlineButtonStyle())
                }
            }.padding(18)
        }
        .background(Palette.paper).navigationTitle("Проверка билетов")
        // The wallet sheet can only come up once the scanner has gone.
        .sheet(isPresented: $scanning, onDismiss: {
            if let scanned { code = scanned; wallet.checkIn(code: scanned) }
            scanned = nil
        }) {
            TicketScanner { value in scanned = value; scanning = false }.ignoresSafeArea()
        }
    }
}

/// Live camera scanner for the QR code on a ticket.
struct TicketScanner: UIViewControllerRepresentable {
    @MainActor static var isSupported: Bool { DataScannerViewController.isSupported }
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var found = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !found, case .barcode(let barcode)? = addedItems.first, let value = barcode.payloadStringValue else { return }
            found = true
            dataScanner.stopScanning()
            onCode(value)
        }
    }
}
