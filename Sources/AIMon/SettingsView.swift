import SwiftUI
import AppKit
import AIMonCore

/// Backing state for the Settings window: live Ollama status, installed models, and model download.
@MainActor
final class SettingsViewModel: ObservableObject {
    enum Status: Equatable { case checking, running, notRunning, notInstalled }

    @Published var ollamaEnabled: Bool
    @Published var selectedModel: String?
    @Published var status: Status = .checking
    @Published var installedModels: [String] = []
    @Published var downloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?

    let recommendation: ModelRecommendation
    private let store: SettingsStore
    private let service = OllamaService()

    init(store: SettingsStore) {
        self.store = store
        self.ollamaEnabled = store.settings.ollamaEnabled
        self.selectedModel = store.settings.selectedModel
        self.recommendation = HardwareAdvisor.recommendedModel(forRAMBytes: ProcessInfo.processInfo.physicalMemory)
    }

    var logPath: String { Log.fileURL.path }
    var recommendedInstalled: Bool { installedModels.contains(recommendation.model) }

    func setEnabled(_ on: Bool) {
        ollamaEnabled = on
        store.update { $0.ollamaEnabled = on }
        if on { Task { await refresh() } }
    }

    func selectModel(_ model: String?) {
        selectedModel = model
        store.update { $0.selectedModel = model }
    }

    /// Re-query the server: running? which models are installed? (Call from the Refresh button too,
    /// since the user may `ollama pull` more models while AIMon is running.)
    func refresh() async {
        status = .checking
        if await service.isRunning() {
            installedModels = await service.installedModels()
            status = .running
            // Keep a valid selection: prefer the recommended model, else the first installed.
            if selectedModel == nil || !installedModels.contains(selectedModel!) {
                selectModel(installedModels.contains(recommendation.model) ? recommendation.model : installedModels.first)
            }
        } else {
            installedModels = []
            status = service.isInstalled() ? .notRunning : .notInstalled
        }
    }

    func download() {
        downloading = true; downloadProgress = 0; downloadError = nil
        Task {
            do {
                try await service.pull(recommendation.model) { frac in
                    Task { @MainActor in self.downloadProgress = frac }
                }
                downloading = false
                await refresh()
                selectModel(recommendation.model)
            } catch {
                downloading = false
                downloadError = error.localizedDescription
            }
        }
    }

    func revealLogs() { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
}

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.bold())
            speech
            Divider()
            logs
            Spacer(minLength: 0)
            Text("AIMon works fully offline with built-in lines. A local AI model just makes the chatter richer and more in-character.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440, height: 420)
        .task { await vm.refresh() }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speech").font(.headline)
            Toggle("Use a local AI model (Ollama) for richer speech",
                   isOn: Binding(get: { vm.ollamaEnabled }, set: { vm.setEnabled($0) }))
            statusRow
            if vm.ollamaEnabled && vm.status == .running {
                HStack(spacing: 8) {
                    Picker("Model", selection: Binding(get: { vm.selectedModel ?? "" },
                                                       set: { vm.selectModel($0.isEmpty ? nil : $0) })) {
                        if vm.installedModels.isEmpty { Text("None installed").tag("") }
                        ForEach(vm.installedModels, id: \.self) { Text($0).tag($0) }
                    }
                    Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh installed models")
                }
                recommendation
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 6) {
            switch vm.status {
            case .checking:
                ProgressView().controlSize(.small); Text("Checking Ollama…").foregroundStyle(.secondary)
            case .running:
                Circle().fill(.green).frame(width: 8, height: 8); Text("Ollama is running").foregroundStyle(.secondary)
            case .notRunning:
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("Ollama is installed but not running — open the Ollama app.").foregroundStyle(.secondary)
            case .notInstalled:
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("Ollama not found.").foregroundStyle(.secondary)
                Link("Get Ollama", destination: URL(string: "https://ollama.com")!)
            }
        }
        .font(.caption)
    }

    @ViewBuilder private var recommendation: some View {
        if !vm.recommendedInstalled {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended for your Mac: \(vm.recommendation.model) (~\(String(format: "%.1f", vm.recommendation.approxSizeGB)) GB)")
                    .font(.caption).foregroundStyle(.secondary)
                if vm.downloading {
                    ProgressView(value: vm.downloadProgress)
                    Text("Downloading… \(Int(vm.downloadProgress * 100))%").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Button("Download \(vm.recommendation.model)") { vm.download() }
                }
                if let err = vm.downloadError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logs").font(.headline)
            Button("Reveal log file in Finder") { vm.revealLogs() }
            Text(vm.logPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
        }
    }
}
