import Foundation

enum AnalysisRunMode: String, Hashable, Codable, Sendable {
    case localFirst
    case improvedWithNetwork

    var allowsNetworkAccess: Bool {
        self == .improvedWithNetwork
    }

    var shortTitle: String {
        switch self {
        case .localFirst:
            return "Local"
        case .improvedWithNetwork:
            return "Improved"
        }
    }
}

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

struct GroupSimilarityDiagnostics: Hashable, Codable, Sendable {
    let edgeCount: Int
    let minEdgeGapSeconds: TimeInterval
    let maxEdgeGapSeconds: TimeInterval
    let averageEdgeGapSeconds: TimeInterval
    let minHashDistance: Double
    let maxHashDistance: Double
    let averageHashDistance: Double
    let visionEdgeCount: Int
    let minVisionDistance: Float?
    let maxVisionDistance: Float?
    let averageVisionDistance: Float?
}

struct GroupRankingDiagnostics: Hashable, Codable, Sendable {
    let firstPassWinnerAssetID: String
    let finalWinnerAssetID: String
    let firstPassTopGap: Double?
    let secondPassTriggered: Bool
    let secondPassCandidateCount: Int
    let secondPassExtractionCount: Int
    let winnerChanged: Bool
    let winnerChangeMargin: Double?
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
    let similarityDiagnostics: GroupSimilarityDiagnostics?
    let rankingDiagnostics: GroupRankingDiagnostics?

    var count: Int { assets.count }
}

struct AnalysisDiagnostics: Hashable, Codable, Sendable {
    let sequenceCount: Int
    let featureExtractionCount: Int
    let similarityEdgeCount: Int
    let groupCount: Int
}

struct AssetAvailabilityDiagnostics: Hashable, Codable, Sendable {
    let processedFeatureCount: Int
    let degradedThumbnailCount: Int
    let skippedNoLocalThumbnailCount: Int
}

struct MonthAssetSnapshot: Hashable, Codable, Sendable {
    let assetCount: Int
    let oldestAssetID: String?
    let newestAssetID: String?
    let oldestCreationDate: Date?
    let newestCreationDate: Date?
    let sampledAssetIDs: [String]
    let fullContentSignature: String?

    init(
        assetCount: Int,
        oldestAssetID: String?,
        newestAssetID: String?,
        oldestCreationDate: Date?,
        newestCreationDate: Date?,
        sampledAssetIDs: [String],
        fullContentSignature: String? = nil
    ) {
        self.assetCount = assetCount
        self.oldestAssetID = oldestAssetID
        self.newestAssetID = newestAssetID
        self.oldestCreationDate = oldestCreationDate
        self.newestCreationDate = newestCreationDate
        self.sampledAssetIDs = sampledAssetIDs
        self.fullContentSignature = fullContentSignature
    }
}

struct MonthAnalysisResult: Hashable, Codable, Sendable {
    let selection: MonthSelection
    let generatedAt: Date
    let assetCountAnalyzed: Int
    let groups: [SimilarPhotoGroup]
    let librarySnapshot: MonthAssetSnapshot?
    let config: AnalysisConfiguration
    let diagnostics: AnalysisDiagnostics?
    let runMode: AnalysisRunMode?
    let assetAvailabilityDiagnostics: AssetAvailabilityDiagnostics?
    let cacheValidationMode: CacheValidationMode?

    init(
        selection: MonthSelection,
        generatedAt: Date,
        assetCountAnalyzed: Int,
        groups: [SimilarPhotoGroup],
        librarySnapshot: MonthAssetSnapshot?,
        config: AnalysisConfiguration,
        diagnostics: AnalysisDiagnostics?,
        runMode: AnalysisRunMode? = nil,
        assetAvailabilityDiagnostics: AssetAvailabilityDiagnostics? = nil,
        cacheValidationMode: CacheValidationMode? = nil
    ) {
        self.selection = selection
        self.generatedAt = generatedAt
        self.assetCountAnalyzed = assetCountAnalyzed
        self.groups = groups
        self.librarySnapshot = librarySnapshot
        self.config = config
        self.diagnostics = diagnostics
        self.runMode = runMode
        self.assetAvailabilityDiagnostics = assetAvailabilityDiagnostics
        self.cacheValidationMode = cacheValidationMode
    }
}

struct AnalysisProgress: Hashable, Sendable {
    let stage: String
    let completedUnits: Int
    let totalUnits: Int

    static let idle = AnalysisProgress(stage: "Idle", completedUnits: 0, totalUnits: 0)
}
