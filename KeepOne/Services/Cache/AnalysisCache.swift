import Foundation

protocol AnalysisCacheProtocol {
    func load(selection: MonthSelection) -> MonthAnalysisResult?
    func save(_ result: MonthAnalysisResult) throws
    func invalidate(selection: MonthSelection) throws
    func hasCachedResult(selection: MonthSelection) -> Bool
}

final class AnalysisCache: AnalysisCacheProtocol {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let cachesBaseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = cachesBaseURL.appendingPathComponent("KeepOneAnalysisCache", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func load(selection: MonthSelection) -> MonthAnalysisResult? {
        let url = cacheFileURL(selection: selection)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(MonthAnalysisResult.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ result: MonthAnalysisResult) throws {
        let data = try encoder.encode(result)
        let url = cacheFileURL(selection: result.selection)
        try data.write(to: url, options: [.atomic])
    }

    func invalidate(selection: MonthSelection) throws {
        let url = cacheFileURL(selection: selection)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func hasCachedResult(selection: MonthSelection) -> Bool {
        fileManager.fileExists(atPath: cacheFileURL(selection: selection).path)
    }

    private func cacheFileURL(selection: MonthSelection) -> URL {
        directoryURL.appendingPathComponent("\(selection.id).json", isDirectory: false)
    }
}
