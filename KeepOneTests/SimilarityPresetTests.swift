import Foundation
import XCTest
@testable import KeepOne

final class SimilarityPresetTests: XCTestCase {
    func testPresetThresholdOrdering() {
        XCTAssertLessThan(SimilarityPreset.strict.visionDistanceThreshold, SimilarityPreset.balanced.visionDistanceThreshold)
        XCTAssertLessThan(SimilarityPreset.balanced.visionDistanceThreshold, SimilarityPreset.relaxed.visionDistanceThreshold)
        XCTAssertLessThan(SimilarityPreset.strict.hashDistanceThreshold, SimilarityPreset.balanced.hashDistanceThreshold)
        XCTAssertLessThan(SimilarityPreset.balanced.hashDistanceThreshold, SimilarityPreset.relaxed.hashDistanceThreshold)
    }

    func testSettingsSnapshotDecodesLegacyPayloadWithBalancedPresetDefault() throws {
        let legacyJSON = """
        {
          "temporalGapSeconds": 300,
          "gapHistory": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AnalysisSettingsSnapshot.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(snapshot.temporalGapSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(snapshot.similarityPreset, .balanced)
        XCTAssertEqual(snapshot.cacheValidationMode, .lightweightSnapshot)
        XCTAssertTrue(snapshot.presetHistory.isEmpty)
        XCTAssertTrue(snapshot.cacheValidationHistory.isEmpty)
    }

    func testApplyPresetUpdatesConfigThresholds() {
        var config = AnalysisConfiguration.default
        config.applySimilarityPreset(.strict)

        XCTAssertEqual(config.similarityPreset, .strict)
        XCTAssertEqual(config.visionDistanceThreshold, SimilarityPreset.strict.visionDistanceThreshold)
        XCTAssertEqual(config.hashDistanceThreshold, SimilarityPreset.strict.hashDistanceThreshold, accuracy: 0.0001)
    }
}
