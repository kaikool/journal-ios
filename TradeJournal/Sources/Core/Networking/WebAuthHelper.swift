import Foundation
import AuthenticationServices

#if canImport(UIKit)
import UIKit
#endif

/// Domain specification matching core web repository
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
        // 1. Look for foreground active window scene
        for scene in scenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let firstWindow = windowScene.windows.first {
                return firstWindow
            }
        }
        // 2. Fallback to any window scene
        for scene in scenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let firstWindow = windowScene.windows.first {
                return firstWindow
            }
        }
        // 3. Fallback: create window attached to first scene
        if let windowScene = scenes.compactMap({ $0 as? UIWindowScene }).first {
            return UIWindow(windowScene: windowScene)
        }
        return UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
