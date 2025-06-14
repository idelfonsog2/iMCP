import Foundation
import FoundationModels

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
protocol Service {
    var name: String { get }
    var description: String { get }
    var isEnabled: Bool { get set }
    
    var tools: [any FoundationModels.Tool] { get }
    
    var isActivated: Bool { get async }
    func activate() async throws
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
extension Service {
    var isActivated: Bool {
        get async {
            return isEnabled
        }
    }

    func activate() async throws {
        // Default implementation - services can override if needed
    }
}
