import Foundation
import AuthenticationServices

#if canImport(UIKit)
import UIKit
#endif

/// Trình quản lý luồng đăng nhập Web OAuth an toàn qua ASWebAuthenticationSession trên iOS
@MainActor
public final class WebAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = WebAuthHelper()
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func startSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first { $0.isKeyWindow } ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
