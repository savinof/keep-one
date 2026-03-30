import Foundation

struct PhotoAssetRef: Identifiable, Hashable, Codable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let mediaSubtypesRawValue: UInt
    let burstIdentifier: String?
    let burstSelectionTypesRawValue: UInt
    let isFavorite: Bool

    var id: String { localIdentifier }
    var pixelCount: Int { max(1, pixelWidth * pixelHeight) }
}

struct YearSection: Identifiable, Hashable, Codable, Sendable {
    let year: Int
    let assetCount: Int

    var id: Int { year }
}

struct MonthSection: Identifiable, Hashable, Codable, Sendable {
    let year: Int
    let month: Int
    let assetCount: Int

    var id: String { MonthSelection(year: year, month: month).id }
    var selection: MonthSelection { MonthSelection(year: year, month: month) }

    var title: String {
        MonthSelection.monthFormatter.string(from: selection.startDate)
    }
}

struct MonthSelection: Identifiable, Hashable, Codable, Sendable {
    let year: Int
    let month: Int

    var id: String { String(format: "%04d-%02d", year, month) }

    var startDate: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Self.calendar.date(from: components) ?? .distantPast
    }

    var endDate: Date {
        let nextMonth = Self.calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate
        return nextMonth
    }

    var displayTitle: String {
        Self.monthFormatter.string(from: startDate)
    }

    static let calendar = Calendar(identifier: .gregorian)

    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

struct TemporalSequence: Identifiable, Hashable, Sendable {
    let id: Int
    let assets: [PhotoAssetRef]

    var startDate: Date? { assets.compactMap(\.creationDate).min() }
    var endDate: Date? { assets.compactMap(\.creationDate).max() }
}

struct RankedPhotoCandidate: Identifiable, Hashable, Codable, Sendable {
    let asset: PhotoAssetRef
    let score: Double
    let reasons: [String]

    var id: String { asset.localIdentifier }
}

struct SimilarPhotoGroup: Identifiable, Hashable, Codable, Sendable {
    struct DateRange: Hashable, Codable, Sendable {
        let start: Date
        let end: Date
    }

    let id: String
    let assets: [PhotoAssetRef]
    let representativeAssetID: String
    let suggestedBestAssetID: String
    let rankedCandidates: [RankedPhotoCandidate]
    let dateRange: DateRange?

    var count: Int { assets.count }
}

struct AnalysisDiagnostics: Hashable, Codable, Sendable {
    let sequenceCount: Int
    let featureExtractionCount: Int
    let similarityEdgeCount: Int
    let groupCount: Int
}

struct MonthAnalysisResult: Hashable, Codable, Sendable {
    let selection: MonthSelection
    let generatedAt: Date
    let assetCountAnalyzed: Int
    let groups: [SimilarPhotoGroup]
    let config: AnalysisConfiguration
    let diagnostics: AnalysisDiagnostics?
}

struct AnalysisProgress: Hashable, Sendable {
    let stage: String
    let completedUnits: Int
    let totalUnits: Int

    static let idle = AnalysisProgress(stage: "Idle", completedUnits: 0, totalUnits: 0)
}
