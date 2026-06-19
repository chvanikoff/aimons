import Foundation

/// A suggested local model for the speech engine, with an approximate download size.
public struct ModelRecommendation: Equatable, Sendable {
    public let model: String
    public let approxSizeGB: Double
    public init(model: String, approxSizeGB: Double) {
        self.model = model; self.approxSizeGB = approxSizeGB
    }
}

/// Picks a sensible default Ollama model for the machine. RAM is the binding constraint for these
/// short, in-character bubbles — no need for a giant model. (See the project's model-defaults notes.)
public enum HardwareAdvisor {
    public static func recommendedModel(forRAMBytes ram: UInt64) -> ModelRecommendation {
        let gb = Double(ram) / 1_073_741_824
        switch gb {
        case ..<24:   return ModelRecommendation(model: "llama3.2:3b", approxSizeGB: 2.0)
        case 24..<32: return ModelRecommendation(model: "qwen2.5:7b",  approxSizeGB: 4.7)
        default:      return ModelRecommendation(model: "qwen2.5:14b", approxSizeGB: 9.0)
        }
    }
}
