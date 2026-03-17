import Foundation

enum InferenceRuntime: String, CaseIterable, Identifiable {
    case dryRun = "Dry Run"
    case nativeLlamaCpp = "Native (llama.cpp)"

    var id: String { rawValue }
}

enum InferenceError: LocalizedError {
    case modelFilesMissing([String])
    case unsupportedBackend(String)
    case llamaCppNotLinked

    var errorDescription: String? {
        switch self {
        case let .modelFilesMissing(files):
            return "Missing files: \(files.joined(separator: ", "))"
        case let .unsupportedBackend(name):
            return "Unsupported backend: \(name)"
        case .llamaCppNotLinked:
            return "llama.cpp runtime is not linked yet. Next step: add native llama.cpp bridge (C/C++) and call it from VLMInferenceEngine."
        }
    }
}
