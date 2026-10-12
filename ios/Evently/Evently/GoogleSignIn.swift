import AuthenticationServices
import CryptoKit
import UIKit

enum GoogleSignInError: LocalizedError {
    case notConfigured
    case failed
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Вход через Google ещё не настроен в этой сборке"
        case .failed: "Не удалось войти через Google. Попробуй ещё раз"
        }
    }
}

/// OAuth 2.0 for native apps: system browser sheet + PKCE, no client secret and no embedded WebView.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSignIn()
    private var session: ASWebAuthenticationSession?

    static var clientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.hasSuffix(".apps.googleusercontent.com") ? value : nil
    }

    /// Returns a Google ID token, or nil when the user closes the sheet.
    func idToken() async throws -> String? {
        guard let clientID = Self.clientID else { throw GoogleSignInError.notConfigured }
        // Google issues iOS clients a redirect scheme that is the client ID reversed.
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.random()
        let state = Self.random()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account")
        ]
        guard let callback = try await authorize(components.url!, scheme: scheme) else { return nil }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleSignInError.failed }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "code_verifier", value: verifier)
        ]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["id_token"] as? String else { throw GoogleSignInError.failed }
        return token
    }

    private func authorize(_ url: URL, scheme: String) async throws -> URL? {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(returning: nil) }
                else { continuation.resume(throwing: GoogleSignInError.failed) }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: GoogleSignInError.failed) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? ASPresentationAnchor()
    }

    private static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
