import Foundation
import UIKit

struct VLMRunResult {
    let outputText: String
    let ttftSeconds: Double
    let tokensPerSecond: Double
    let elapsedSeconds: Double
    let residentMemoryMB: Double
}

enum VLMInferenceEngine {
    static func run(
        model: LocalModelOption,
        prompt: String,
        image: UIImage?,
        runtime: InferenceRuntime,
        modelsRoot: URL
    ) async throws -> VLMRunResult {
        let missing = model.missingFiles(in: modelsRoot)
        if !missing.isEmpty {
            throw InferenceError.modelFilesMissing(missing)
        }

        switch runtime {
        case .dryRun:
            return try await runDryTest(model: model, prompt: prompt, image: image)
        case .nativeLlamaCpp:
            return try await runNativeLlamaCpp(model: model, prompt: prompt, image: image, modelsRoot: modelsRoot)
        }
    }

    private static func runDryTest(
        model: LocalModelOption,
        prompt: String,
        image: UIImage?
    ) async throws -> VLMRunResult {
        let start = Date()
        try await Task.sleep(nanoseconds: 400_000_000)
        let ttft = Date().timeIntervalSince(start)
        try await Task.sleep(nanoseconds: 900_000_000)
        let elapsed = Date().timeIntervalSince(start)

        let imageFlag = image == nil ? "without image" : "with image"
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrompt = trimmedPrompt.isEmpty ? "(empty prompt)" : trimmedPrompt

        return VLMRunResult(
            outputText: "[DRY-RUN] \(model.displayName) \(imageFlag). Prompt: \(safePrompt)",
            ttftSeconds: ttft,
            tokensPerSecond: 22.0,
            elapsedSeconds: elapsed,
            residentMemoryMB: MemoryStats.residentMB()
        )
    }

    private static func runNativeLlamaCpp(
        model: LocalModelOption,
        prompt: String,
        image: UIImage?,
        modelsRoot: URL
    ) async throws -> VLMRunResult {
        switch model.backend {
        case .ggufLlamaCpp:
            guard let mainModelFile = model.mainModelFile else {
                throw InferenceError.modelFilesMissing(["mainModelFile is not configured"])
            }

            guard let mainModelURL = model.resolvedFileURL(fileName: mainModelFile, in: modelsRoot) else {
                throw InferenceError.modelFilesMissing([mainModelFile])
            }
            let mmprojPath = try model.mmprojFile.map { mmprojFileName in
                guard let mmprojURL = model.resolvedFileURL(fileName: mmprojFileName, in: modelsRoot) else {
                    throw InferenceError.modelFilesMissing([mmprojFileName])
                }
                return mmprojURL.path
            }

            let imagePath = try writeImageToTemporaryFileIfNeeded(image)
            defer {
                if let imagePath {
                    try? FileManager.default.removeItem(atPath: imagePath)
                }
            }

            let bridge = LlamaCppBridge()
            try bridge.open(modelPath: mainModelURL.path, mmprojPath: mmprojPath)
            let runResult = try runWithFallbackPromptIfNeeded(
                bridge: bridge,
                prompt: prompt,
                imagePath: imagePath
            )
            let ttft = runResult.firstTokenLatencySeconds ?? runResult.elapsedSeconds
            let tps: Double
            if runResult.elapsedSeconds > 0 {
                tps = Double(runResult.generatedTokenCount) / runResult.elapsedSeconds
            } else {
                tps = 0
            }
            let cleaned = sanitizeOutput(runResult.text)

            return VLMRunResult(
                outputText: cleaned.isEmpty ? "(empty output)" : cleaned,
                ttftSeconds: ttft,
                tokensPerSecond: tps,
                elapsedSeconds: runResult.elapsedSeconds,
                residentMemoryMB: MemoryStats.residentMB()
            )
        case .transformers:
            throw InferenceError.unsupportedBackend(model.backend.rawValue)
        }
    }

    private static func writeImageToTemporaryFileIfNeeded(_ image: UIImage?) throws -> String? {
        guard let image else { return nil }
        let resized = downscaleIfNeeded(image, maxSide: 896)
        guard let data = resized.jpegData(compressionQuality: 0.9) else { return nil }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlm_input_\(UUID().uuidString).jpg")
        try data.write(to: path)
        return path.path
    }

    private static func downscaleIfNeeded(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > maxSide else { return image }

        let scale = maxSide / longSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func sanitizeOutput(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: "</think>", with: "")
        out = out.replacingOccurrences(of: "<think>", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runWithFallbackPromptIfNeeded(
        bridge: LlamaCppBridge,
        prompt: String,
        imagePath: String?
    ) throws -> LlamaCppRunResult {
        do {
            return try bridge.run(prompt: prompt, imagePath: imagePath)
        } catch let LlamaCppBridgeError.runFailed(code, message) where code == -13 {
            let fallbackPrompt = """
            Describe this image in English in one paragraph.
            Then list exactly 3 key objects.
            If there is visible text in the image, include it.
            """
            print("[VLM][RETRY] reason=no-token-generated code=\(code) message=\(message)")
            return try bridge.run(prompt: fallbackPrompt, imagePath: imagePath)
        }
    }
}
