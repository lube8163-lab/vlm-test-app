import Foundation

struct LocalModelOption: Identifiable, Hashable {
    enum Backend: String, CaseIterable {
        case ggufLlamaCpp = "GGUF / llama.cpp"
        case transformers = "Transformers"
    }

    let id: String
    let displayName: String
    let backend: Backend
    let relativeDirectory: String
    let requiredFiles: [String]
    let mainModelFile: String?
    let mmprojFile: String?
    let sourceURL: String?

    func destinationDirectoryURL(in modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
    }

    func destinationFileURL(fileName: String, in modelsRoot: URL) -> URL {
        destinationDirectoryURL(in: modelsRoot).appendingPathComponent(fileName)
    }

    func resolvedFileURL(fileName: String, in modelsRoot: URL) -> URL? {
        let fm = FileManager.default

        let docsURL = destinationFileURL(fileName: fileName, in: modelsRoot)
        if fm.fileExists(atPath: docsURL.path) {
            return docsURL
        }

        return nil
    }

    func missingFiles(in modelsRoot: URL) -> [String] {
        requiredFiles.filter { file in
            resolvedFileURL(fileName: file, in: modelsRoot) == nil
        }
    }
}

enum ModelCatalog {
    static let defaults: [LocalModelOption] = [
        LocalModelOption(
            id: "qwen-3.5-0.8b-gguf",
            displayName: "Qwen3.5-0.8B (GGUF)",
            backend: .ggufLlamaCpp,
            relativeDirectory: "qwen3_5_0_8b_gguf",
            requiredFiles: ["Qwen3.5-0.8B-Q4_K_M.gguf"],
            mainModelFile: "Qwen3.5-0.8B-Q4_K_M.gguf",
            mmprojFile: nil,
            sourceURL: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF"
        ),
        LocalModelOption(
            id: "moondream2-gguf",
            displayName: "moondream2 (GGUF text+mmproj)",
            backend: .ggufLlamaCpp,
            relativeDirectory: "moondream2",
            requiredFiles: ["moondream2-text-model-f16.gguf", "moondream2-mmproj-f16.gguf"],
            mainModelFile: "moondream2-text-model-f16.gguf",
            mmprojFile: "moondream2-mmproj-f16.gguf",
            sourceURL: "https://huggingface.co/vikhyatk/moondream2"
        ),
        LocalModelOption(
            id: "moondream2-gguf-q4km",
            displayName: "moondream2 (GGUF Q4_K_M + mmproj)",
            backend: .ggufLlamaCpp,
            relativeDirectory: "moondream2",
            requiredFiles: ["moondream2-text-model-q4_k_m.gguf", "moondream2-mmproj-f16.gguf"],
            mainModelFile: "moondream2-text-model-q4_k_m.gguf",
            mmprojFile: "moondream2-mmproj-f16.gguf",
            sourceURL: "https://huggingface.co/vikhyatk/moondream2"
        ),
        LocalModelOption(
            id: "qwen-3.5-vl-0.8b-gguf",
            displayName: "Qwen3.5-VL-0.8B (GGUF + mmproj)",
            backend: .ggufLlamaCpp,
            relativeDirectory: "qwen3_5_vl_0_8b_gguf",
            requiredFiles: ["Qwen3.5-0.8B-Q4_K_M.gguf", "mmproj-F16.gguf"],
            mainModelFile: "Qwen3.5-0.8B-Q4_K_M.gguf",
            mmprojFile: "mmproj-F16.gguf",
            sourceURL: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF"
        ),
        LocalModelOption(
            id: "gemma-4-e2b-it-gguf",
            displayName: "Gemma 4 E2B-It (GGUF + mmproj)",
            backend: .ggufLlamaCpp,
            relativeDirectory: "gemma4_e2b_it_gguf",
            requiredFiles: ["gemma-4-E2B-it-Q4_K_M.gguf", "mmproj-F16.gguf"],
            mainModelFile: "gemma-4-E2B-it-Q4_K_M.gguf",
            mmprojFile: "mmproj-F16.gguf",
            sourceURL: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF"
        )
    ]

    static func availableModels(in modelsRoot: URL) -> [LocalModelOption] {
        defaults + autodetectedModels(in: modelsRoot)
    }

    private static func autodetectedModels(in modelsRoot: URL) -> [LocalModelOption] {
        let fm = FileManager.default
        let knownDirs = Set(defaults.map(\.relativeDirectory))

        guard let entries = try? fm.contentsOfDirectory(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [LocalModelOption] = []

        for entry in entries {
            guard knownDirs.contains(entry.lastPathComponent) == false else { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let ggufs = files
                .filter { $0.pathExtension.lowercased() == "gguf" }
                .map(\.lastPathComponent)

            guard ggufs.isEmpty == false else { continue }

            let mmproj = ggufs.first { $0.lowercased().contains("mmproj") }
            let mainCandidates = ggufs.filter { $0 != mmproj }

            for main in mainCandidates {
                let baseID = "custom-\(entry.lastPathComponent)-\(main)"
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                let required = mmproj.map { [main, $0] } ?? [main]
                results.append(
                    LocalModelOption(
                        id: baseID,
                        displayName: "\(entry.lastPathComponent) (\(main))",
                        backend: .ggufLlamaCpp,
                        relativeDirectory: entry.lastPathComponent,
                        requiredFiles: required,
                        mainModelFile: main,
                        mmprojFile: mmproj,
                        sourceURL: nil
                    )
                )
            }
        }

        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
