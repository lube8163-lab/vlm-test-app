//
//  ContentView.swift
//  vlm_test
//
//  Created by Tasuku Kato on 2026/03/03.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum ImportMode {
        case requiredForSelectedModel
        case customModelFiles
    }

    @State private var modelsRootPath: String = ContentView.defaultModelsRootPath()
    @State private var selectedModelID: String = ModelCatalog.defaults.first?.id ?? ""
    @State private var selectedRuntime: InferenceRuntime = .nativeLlamaCpp
    @State private var promptText: String = "Describe this image in English as a Stable Diffusion prompt. Include subject, composition, lighting, camera angle/lens feel, style keywords, and 3 negative prompts."
    @State private var outputText: String = ""

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    @State private var isRunning = false
    @State private var errorMessage: String?

    @State private var ttftSeconds: Double?
    @State private var tokensPerSecond: Double?
    @State private var elapsedSeconds: Double?
    @State private var residentMemoryMB: Double?
    @State private var importMessage: String?
    @State private var isImportingModelFiles = false
    @State private var importMode: ImportMode = .requiredForSelectedModel
    @FocusState private var isPromptFocused: Bool

    private var modelsRootURL: URL {
        URL(fileURLWithPath: modelsRootPath, isDirectory: true)
    }

    private var availableModels: [LocalModelOption] {
        ModelCatalog.availableModels(in: modelsRootURL)
    }

    private var selectedModel: LocalModelOption? {
        availableModels.first(where: { $0.id == selectedModelID })
    }

    private var modelMissingFiles: [String] {
        guard let selectedModel else { return [] }
        return selectedModel.missingFiles(in: modelsRootURL)
    }

    private var canRun: Bool {
        !isRunning && selectedModel != nil && modelMissingFiles.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    TextField("Models root", text: $modelsRootPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onTapGesture {
                            isPromptFocused = false
                        }
                    Button("Use App Documents/Models") {
                        isPromptFocused = false
                        modelsRootPath = Self.defaultModelsRootPath()
                    }
                    .font(.footnote)
                    if selectedModel != nil {
                        Button("Import Required Files from Files") {
                            isPromptFocused = false
                            importMode = .requiredForSelectedModel
                            isImportingModelFiles = true
                        }
                        .font(.footnote)
                        Text("Download model files in the iPhone Files app, then import only the filenames listed below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Import Custom GGUF/mmproj from Files") {
                        isPromptFocused = false
                        importMode = .customModelFiles
                        isImportingModelFiles = true
                    }
                    .font(.footnote)
                    Text("Use this for unsupported models. Select the main GGUF and optional mmproj together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Runtime", selection: $selectedRuntime) {
                        ForEach(InferenceRuntime.allCases) { runtime in
                            Text(runtime.rawValue).tag(runtime)
                        }
                    }
                    .onChange(of: selectedRuntime) { _, _ in
                        isPromptFocused = false
                    }
                    if selectedRuntime == .nativeLlamaCpp {
                        Text("Native mode uses local llama.cpp runtime (text and image for mmproj models).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Target", selection: $selectedModelID) {
                        ForEach(availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .onChange(of: selectedModelID) { _, _ in
                        isPromptFocused = false
                    }
                    if let selectedModel {
                        LabeledContent("Backend", value: selectedModel.backend.rawValue)
                        if modelMissingFiles.isEmpty {
                            Label("Required files found", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Missing files", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                ForEach(modelMissingFiles, id: \.self) { file in
                                    Text("- \(file)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                Section("Input") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(selectedImage == nil ? "Pick Image" : "Change Image", systemImage: "photo")
                    }
                    .onChange(of: selectedPhotoItem) { _, _ in
                        Task {
                            await loadSelectedImage()
                        }
                    }

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                    }

                    TextField("Prompt", text: $promptText, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isPromptFocused)
                }

                Section("Run") {
                    Button(isRunning ? "Running..." : "Run Test") {
                        Task {
                            isPromptFocused = false
                            await runTest()
                        }
                    }
                    .disabled(!canRun)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    if let importMessage {
                        Text(importMessage)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                Section("Metrics") {
                    metricRow(title: "TTFT", value: ttftSeconds.map { String(format: "%.3f s", $0) })
                    metricRow(title: "Tokens / sec", value: tokensPerSecond.map { String(format: "%.2f", $0) })
                    metricRow(title: "Elapsed", value: elapsedSeconds.map { String(format: "%.3f s", $0) })
                    metricRow(title: "Resident RAM", value: residentMemoryMB.map { String(format: "%.0f MB", $0) })
                }

                Section("Output") {
                    Text(outputText.isEmpty ? "No output yet." : outputText)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("On-device VLM Test")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPromptFocused = false
                    }
                }
            }
            .onAppear {
                ensureModelsDirectoryExists()
                if availableModels.contains(where: { $0.id == selectedModelID }) == false,
                   let first = availableModels.first {
                    selectedModelID = first.id
                }
            }
            .fileImporter(
                isPresented: $isImportingModelFiles,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        }
    }

    @ViewBuilder
    private func metricRow(title: String, value: String?) -> some View {
        LabeledContent(title) {
            Text(value ?? "-")
                .monospacedDigit()
        }
    }

    private func loadSelectedImage() async {
        guard let selectedPhotoItem else {
            selectedImage = nil
            return
        }
        do {
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
            }
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }

    private func runTest() async {
        guard let selectedModel else { return }

        isRunning = true
        errorMessage = nil
        importMessage = nil
        outputText = ""
        ttftSeconds = nil
        tokensPerSecond = nil
        elapsedSeconds = nil
        residentMemoryMB = nil

        defer { isRunning = false }

        do {
            let result = try await VLMInferenceEngine.run(
                model: selectedModel,
                prompt: promptText,
                image: selectedImage,
                runtime: selectedRuntime,
                modelsRoot: modelsRootURL
            )
            outputText = result.outputText
            ttftSeconds = result.ttftSeconds
            tokensPerSecond = result.tokensPerSecond
            elapsedSeconds = result.elapsedSeconds
            residentMemoryMB = result.residentMemoryMB

            let ts = ISO8601DateFormatter().string(from: Date())
            print("[VLM][RESULT] ts=\(ts) model=\(selectedModel.id) ttft=\(String(format: "%.3f", result.ttftSeconds)) tps=\(String(format: "%.2f", result.tokensPerSecond)) elapsed=\(String(format: "%.3f", result.elapsedSeconds)) ram_mb=\(String(format: "%.0f", result.residentMemoryMB))")
            print("[VLM][CSV] \(ts),\(selectedModel.id),\(String(format: "%.3f", result.ttftSeconds)),\(String(format: "%.2f", result.tokensPerSecond)),\(String(format: "%.3f", result.elapsedSeconds)),\(String(format: "%.0f", result.residentMemoryMB))")
        } catch {
            errorMessage = error.localizedDescription
            print("[VLM][ERROR] model=\(selectedModel.id) message=\(error.localizedDescription)")
        }
    }

    private static func defaultModelsRootPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let models = docs?.appendingPathComponent("Models", isDirectory: true)
        return models?.path ?? ""
    }

    private func ensureModelsDirectoryExists() {
        let url = URL(fileURLWithPath: modelsRootPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                importMessage = "No files selected."
                return
            }

            switch importMode {
            case .requiredForSelectedModel:
                guard let selectedModel else { return }
                let copied = try importModelFiles(urls: urls, for: selectedModel)
                let remaining = selectedModel.missingFiles(in: modelsRootURL)
                if remaining.isEmpty {
                    importMessage = "Imported \(copied) file(s). All required files are available."
                } else {
                    importMessage = "Imported \(copied) file(s). Still missing: \(remaining.joined(separator: ", "))"
                }
            case .customModelFiles:
                let importedModel = try importCustomModelFiles(urls: urls)
                importMessage = "Imported custom model: \(importedModel.displayName)"
                selectedModelID = importedModel.id
            }
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importModelFiles(urls: [URL], for model: LocalModelOption) throws -> Int {
        let fm = FileManager.default
        let destinationDir = model.destinationDirectoryURL(in: modelsRootURL)
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let required = Set(model.requiredFiles)
        var copied = 0

        for url in urls {
            let fileName = url.lastPathComponent
            guard required.contains(fileName) else { continue }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let destination = model.destinationFileURL(fileName: fileName, in: modelsRootURL)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: url, to: destination)
            copied += 1
        }

        print("[VLM][IMPORT] model=\(model.id) copied=\(copied)")
        return copied
    }

    private func importCustomModelFiles(urls: [URL]) throws -> LocalModelOption {
        let fm = FileManager.default
        let fileNames = urls.map(\.lastPathComponent)
        let ggufs = fileNames.filter { $0.lowercased().hasSuffix(".gguf") }
        let mmproj = ggufs.first { $0.lowercased().contains("mmproj") }
        guard let main = ggufs.first(where: { $0 != mmproj }) else {
            throw NSError(domain: "VLMImport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Select at least one main GGUF file."
            ])
        }

        let baseName = URL(fileURLWithPath: main).deletingPathExtension().lastPathComponent
        let dirName = sanitizedDirectoryName(baseName)
        let destinationDir = modelsRootURL.appendingPathComponent(dirName, isDirectory: true)
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let destination = destinationDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: url, to: destination)
        }

        let model = LocalModelOption(
            id: "custom-\(dirName)-\(main)".lowercased().replacingOccurrences(of: " ", with: "-"),
            displayName: "\(dirName) (\(main))",
            backend: .ggufLlamaCpp,
            relativeDirectory: dirName,
            requiredFiles: mmproj.map { [main, $0] } ?? [main],
            mainModelFile: main,
            mmprojFile: mmproj
        )
        print("[VLM][IMPORT] custom_model=\(model.id)")
        return model
    }

    private func sanitizedDirectoryName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalarView = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let raw = String(scalarView)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
