import Foundation

enum LlamaCppBridgeError: LocalizedError {
    case createFailed(code: Int32, message: String)
    case runFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .createFailed(code, message):
            return "Bridge create failed (\(code)): \(message)"
        case let .runFailed(code, message):
            return "Bridge run failed (\(code)): \(message)"
        }
    }
}

struct LlamaCppRunResult {
    let text: String
    let elapsedSeconds: Double
    let firstTokenLatencySeconds: Double?
    let generatedTokenCount: Int
}

final class LlamaCppBridge {
    private var rawContext: UnsafeMutableRawPointer?

    deinit {
        close()
    }

    func open(modelPath: String, mmprojPath: String?) throws {
        close()

        var ctx: UnsafeMutableRawPointer?
        let result = vlm_create_context(modelPath, mmprojPath, &ctx)
        if result != 0 || ctx == nil {
            let msg = ctx.flatMap { String(cString: vlm_last_error_message($0)) } ?? "unknown"
            throw LlamaCppBridgeError.createFailed(code: result, message: msg)
        }
        rawContext = ctx
    }

    func run(prompt: String, imagePath: String?) throws -> LlamaCppRunResult {
        guard let rawContext else {
            throw LlamaCppBridgeError.createFailed(code: -100, message: "context is not initialized")
        }

        let start = Date()
        let tokenCollector = TokenCollector(start: start)
        let userData = Unmanaged.passRetained(tokenCollector)

        defer {
            userData.release()
        }

        let code = vlm_run(
            rawContext,
            prompt,
            imagePath,
            { tokenPtr, userData in
                guard let tokenPtr, let userData else { return }
                let token = String(cString: tokenPtr)
                let collector = Unmanaged<TokenCollector>.fromOpaque(userData).takeUnretainedValue()
                collector.append(token: token)
            },
            userData.toOpaque()
        )

        if code != 0 {
            let msg = String(cString: vlm_last_error_message(rawContext))
            throw LlamaCppBridgeError.runFailed(code: code, message: msg)
        }

        let elapsed = Date().timeIntervalSince(start)
        return LlamaCppRunResult(
            text: tokenCollector.combinedText,
            elapsedSeconds: elapsed,
            firstTokenLatencySeconds: tokenCollector.firstTokenLatency,
            generatedTokenCount: tokenCollector.tokenCount
        )
    }

    func close() {
        if let rawContext {
            vlm_destroy_context(rawContext)
            self.rawContext = nil
        }
    }
}

private final class TokenCollector {
    private var tokens: [String] = []
    private let start: Date
    private var firstTokenAt: Date?

    var combinedText: String {
        tokens.joined()
    }

    var tokenCount: Int {
        tokens.count
    }

    var firstTokenLatency: Double? {
        guard let firstTokenAt else { return nil }
        return firstTokenAt.timeIntervalSince(start)
    }

    init(start: Date) {
        self.start = start
    }

    func append(token: String) {
        if firstTokenAt == nil {
            firstTokenAt = Date()
        }
        tokens.append(token)
    }
}
