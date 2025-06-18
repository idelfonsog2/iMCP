import Foundation
import FoundationModels

@available(iOS 26.0, *)
protocol Service {
    var name: String { get }
    var description: String { get }
    var isEnabled: Bool { get set }
    
    var tools: [any Tool] { get }
    
    var isActivated: Bool { get async }
    func activate() async throws
}

@available(iOS 26.0, *)
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
