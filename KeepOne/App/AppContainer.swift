import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let photoLibraryService: any PhotoLibraryServiceProtocol
    let thumbnailService: any ThumbnailServiceProtocol
    let monthAnalysisService: any MonthAnalysisServiceProtocol
    let cache: any AnalysisCacheProtocol

    init() {
        let photoLibraryService = PhotoLibraryService()
        let thumbnailService = ThumbnailService(photoLibraryService: photoLibraryService)
        let featureExtractionService = FeatureExtractionService(thumbnailService: thumbnailService)
        let similarityService = SimilarityService()
        let groupingService = GroupingService()
        let rankingService = RankingService()
        let cache = AnalysisCache()
        let analysisService = MonthAnalysisService(
            photoLibraryService: photoLibraryService,
            featureExtractionService: featureExtractionService,
            similarityService: similarityService,
            groupingService: groupingService,
            rankingService: rankingService,
            cache: cache
        )

        self.photoLibraryService = photoLibraryService
        self.thumbnailService = thumbnailService
        self.monthAnalysisService = analysisService
        self.cache = cache
    }
}
