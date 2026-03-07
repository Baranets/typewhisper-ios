import Foundation
import SwiftData
import Combine

@MainActor
final class HistoryService: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []
    var lastRecord: TranscriptionRecord? { records.first }

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init() {
        let schema = Schema([TranscriptionRecord.self])
        let appSupport = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("TypeWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let storeURL = storeDir.appendingPathComponent("history.store")
        let config = ModelConfiguration(url: storeURL)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            for suffix in ["", "-wal", "-shm"] {
                let url = storeDir.appendingPathComponent("history.store\(suffix)")
                try? FileManager.default.removeItem(at: url)
            }
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create history ModelContainer after reset: \(error)")
            }
        }
        modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = true

        fetchRecords()
    }

    func addRecord(
        rawText: String,
        finalText: String,
        appName: String? = nil,
        durationSeconds: Double,
        language: String?,
        engineUsed: String
    ) {
        let record = TranscriptionRecord(
            rawText: rawText,
            finalText: finalText,
            appName: appName,
            durationSeconds: durationSeconds,
            language: language,
            engineUsed: engineUsed
        )
        modelContext.insert(record)
        save()
        fetchRecords()
    }

    func updateRecord(_ record: TranscriptionRecord, finalText: String) {
        record.finalText = finalText
        save()
        fetchRecords()
    }

    func deleteRecord(_ record: TranscriptionRecord) {
        modelContext.delete(record)
        save()
        fetchRecords()
    }

    func deleteRecords(_ records: [TranscriptionRecord]) {
        for record in records {
            modelContext.delete(record)
        }
        save()
        fetchRecords()
    }

    func clearAll() {
        for record in records {
            modelContext.delete(record)
        }
        save()
        fetchRecords()
    }

    func searchRecords(query: String) -> [TranscriptionRecord] {
        guard !query.isEmpty else { return records }
        let lowered = query.lowercased()
        return records.filter {
            $0.finalText.lowercased().contains(lowered)
        }
    }

    func purgeOldRecords(retentionDays: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let old = records.filter { $0.timestamp < cutoff }
        guard !old.isEmpty else { return }
        for record in old {
            modelContext.delete(record)
        }
        save()
        fetchRecords()
    }

    func importKeyboardHistory() {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TypeWhisperConstants.appGroupIdentifier) else { return }

        let fileURL = groupURL.appending(path: TypeWhisperConstants.SharedFiles.keyboardHistoryFile)
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]],
              !entries.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        let existingIds = Set(records.map { $0.id })

        var imported = 0
        for entry in entries {
            guard let idString = entry["id"],
                  let id = UUID(uuidString: idString),
                  !existingIds.contains(id),
                  let finalText = entry["finalText"],
                  !finalText.isEmpty else { continue }

            let record = TranscriptionRecord(
                id: id,
                timestamp: entry["timestamp"].flatMap { formatter.date(from: $0) } ?? Date(),
                rawText: entry["rawText"] ?? finalText,
                finalText: finalText,
                appName: "Keyboard",
                durationSeconds: 0,
                language: entry["language"],
                engineUsed: "keyboard"
            )
            modelContext.insert(record)
            imported += 1
        }

        if imported > 0 {
            save()
            fetchRecords()
        }

        // Clear file after successful import
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fetchRecords() {
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            records = try modelContext.fetch(descriptor)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("HistoryService save error: \(error)")
        }
    }
}
