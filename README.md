# KeepOne (iOS MVP)

KeepOne is a native SwiftUI iOS app MVP that helps users clean up photos by grouping visually similar images and suggesting one photo to keep in each group.

The app is intentionally conservative:
- It analyzes only a user-selected month.
- It does not auto-scan the full library in the background.
- It does not auto-delete anything.
- Deletion only happens after explicit user selection and confirmation.
- Processing is on-device only.

## Product Goal

Reduce decision fatigue for repeated shots by:
1. Selecting a year and month.
2. Grouping similar photos in that month.
3. Ranking photos inside each group.
4. Suggesting one “best” candidate to keep.
5. Letting the user manually choose deletions.

## Architecture Outline

### App + UI Layer
- `RootView` handles permission gating.
- `YearListView` shows available years.
- `MonthListView` shows months for a selected year (with counts and cache marker).
- `MonthAnalysisView` runs/loads month analysis on demand and shows groups.
  - each group card now includes a compact ranking-diagnostics summary
  - includes `Improve` action for optional network-assisted re-analysis
- `GroupDetailView` highlights the suggestion, supports manual multi-select deletion, and asks for confirmation.
  - includes compact “Why suggested” and “Why grouped” diagnostic panels

### ViewModels
- `AppRootViewModel`: permission status and authorization request.
- `YearListViewModel`: year metadata loading.
- `MonthListViewModel`: month metadata loading.
- `MonthAnalysisViewModel`: async analysis state/progress/result.
- `GroupDetailViewModel`: selection and explicit deletion flow.

### Services
- `PhotoLibraryService`:
  - PhotoKit permission handling
  - year/month metadata
  - image fetch for selected month only
  - explicit deletion via `PHPhotoLibrary.performChanges`
- `ThumbnailService`: thumbnail loading and in-memory caching.
  - analysis path supports local-first thumbnail fetch with optional network mode
- `FeatureExtractionService`: per-photo visual features from thumbnails:
  - Vision feature print (when available)
  - perceptual hash fallback
  - blur/sharpness proxy
  - face count and face area proxy
- `SimilarityService`: conservative pair similarity using:
  - Vision feature-print distance threshold first
  - dHash Hamming distance fallback
- `GroupingService`:
  - temporal sequence segmentation
  - similarity adjacency graph
  - connected-components clustering
- `RankingService`:
  - protocol-isolated heuristic scoring
  - outputs sorted candidates + explanation reasons
- `AnalysisCache`:
  - local JSON cache per month (`Caches/KeepOneAnalysisCache/YYYY-MM.json`)
- `AnalysisSettingsStore`:
  - persists similarity settings in JSON
  - tracks temporal-gap and preset change history in the same file
- `MonthAnalysisService`:
  - orchestrates month-only analysis pipeline
  - loads persisted temporal gap + similarity preset at startup
  - uses cache unless re-run forced
  - ignores stale cache when analysis settings changed
  - emits progress strings

## Proposed Folder Structure

```text
KeepOne/
  App/
    AppContainer.swift
    KeepOneApp.swift
  Domain/
    AnalysisConfig.swift
    PhotoModels.swift
  Services/
    Analysis/
      FeatureExtractionService.swift
      GroupingService.swift
      MonthAnalysisService.swift
      RankingService.swift
      SimilarityService.swift
    Cache/
      AnalysisCache.swift
    PhotoLibrary/
      PhotoLibraryService.swift
      ThumbnailService.swift
  ViewModels/
    AppRootViewModel.swift
    GroupDetailViewModel.swift
    MonthAnalysisViewModel.swift
    MonthListViewModel.swift
    YearListViewModel.swift
  Views/
    GroupCardView.swift
    GroupDetailView.swift
    MonthAnalysisView.swift
    MonthListView.swift
    PermissionView.swift
    PhotoThumbnailView.swift
    RootView.swift
    YearListView.swift
  Resources/
    Info.plist
KeepOneTests/
  GraphGroupingTests.swift
  RankingServiceTests.swift
  TemporalSegmentationTests.swift
  TestHelpers.swift
project.yml
README.md
```

## Processing Flow (Mandatory Month-Based Model)

1. Request Photos permission.
2. Fetch and display available years.
3. User selects a year.
4. Fetch and display months for that year.
5. User selects one month.
6. `MonthAnalysisService` (default `Local` run mode):
   - Loads cached result if available (unless force re-run).
   - Otherwise fetches month assets only.
   - Segments by temporal proximity.
   - Computes similarity inside each temporal sequence only.
   - Builds graph + connected components.
   - Keeps groups with size >= 2.
   - Ranks each group and marks a suggested best.
   - Saves result to local cache.
7. User reviews groups and opens detail.
8. User manually selects photos to delete.
9. App asks explicit confirmation.
10. App deletes selected photos only.

Optional refinement:
- User can run `Improve` for the same month.
- The app re-runs analysis with network access enabled for thumbnails to recover iCloud-only items when possible.

## Conservative Grouping Strategy

For the selected month only:
1. Fetch images sorted by creation date.
2. Split into temporal sequences by configurable gap (`default: 5m`, adjustable in app).
   - Burst identifier is used as an additional signal to keep same-burst shots together.
3. Compare images only inside each sequence.
4. Build similarity graph edges under conservative thresholds.
5. Derive groups as connected components.
6. Keep only components with 2+ photos.

No full-library clustering, no all-vs-all across the month.

## Current Similarity Criteria (Relaxed but Controlled)

- Presets:
  - `Strict`: vision `11.5`, hash `0.22`
  - `Balanced` (default): vision `13.0`, hash `0.26`
  - `Relaxed`: vision `14.5`, hash `0.30`
- Thresholds are relaxed by temporal proximity (closer-in-time pairs allow more variation).
- Extra tolerance is applied when both photos likely contain the same subject:
  - both include faces
  - face count is close
  - face area ratio is close
- Mixed cases (face vs no-face) and no-face pairs are evaluated with stricter caps.
- Pairwise graph edges are limited to close capture times (`<= 180s`) unless same burst id.
- After initial edges are built, a coherence pass prunes weak bridge links:
  - keep edge if triangle-supported (shared neighbor), or top match for either endpoint, or a strong edge
  - remove weak links that only chain otherwise unrelated subgroups
- Very large visual distances are still rejected to avoid clear false positives.
- Matching remains sequence-scoped only (month + user-selected time gap), never whole-library.

## Ranking Strategy (Suggestion, Not Guarantee)

`RankingService` computes an explainable heuristic score per photo with signals inspired by Apple’s published high-level direction (multi-signal curation, not a single metric):
- face clarity (count, prominence, centering)
- eye openness (landmark-based proxy when detected)
- expression quality (mouth-shape proxy when detected)
- sharpness proxy (thumbnail gradients)
- composition prominence (saliency + centering)
- exposure balance (brightness + contrast)
- resolution signal
- burst auto-pick bonus (when present)
- favorite bonus
- screenshot penalty

The top score becomes `suggestedBestAssetID`. UI labels it as a suggestion only.
For better tie-breaking quality, analysis can run a second pass on larger thumbnails for the top 2-3 candidates in each group.
This second pass is conservative and only applies when first-pass top candidates are close.
Group detail now exposes per-group ranking diagnostics (first-pass gap, second-pass trigger, and whether the winner changed).

Apple has not publicly documented an exact Featured-Photo/Key-Photo formula, so this MVP uses a transparent on-device approximation.

## Caching Approach

- Cache is local JSON by month key (`YYYY-MM`).
- Opening an already analyzed month returns cache quickly.
- “Re-Run” forces fresh month analysis and rewrites cache.
- If similarity settings differ from the cached run config, cache is skipped and analysis recomputes.
- Cache validity also checks a lightweight month snapshot:
  - asset count
  - oldest/newest asset id + date
  - sampled asset ids across the month timeline
- Optional stronger mode: full month content signature
  - SHA-256 hash over month asset identifiers and key metadata
  - enabled from Settings as `Full Signature`
- If snapshot differs from cached run, cache is treated as stale and analysis recomputes.
- Changing cache-validation mode also forces recompute for deterministic behavior.

## iCloud / Local-Thumbnail Handling

- Default month analysis is local-first:
  - network access disabled for analysis thumbnails
  - uses local preview thumbnail if available (including degraded local previews)
  - skips assets that are iCloud-only with no local representation
- UI now reports availability diagnostics for each run:
  - processed via thumbnails
  - used degraded local previews
  - skipped because not local
- `Improve` re-runs month analysis with network-enabled thumbnail fetch to reduce skipped iCloud-only assets.

### Current Cache Limitations (MVP)
- Snapshot mode is heuristic (fast, lower CPU); full-signature mode is stronger but still metadata-based.
- If user edits/removes photos outside app, cache may become stale until re-run.
- Cache stores final grouped/ranked output only (no feature-level cache).

## Unit Tests (Lightweight)

Included tests cover:
- temporal segmentation (`TemporalSegmentationTests`)
- connected-components graph grouping (`GraphGroupingTests`)
- graph coherence bridge-pruning (`GraphCoherenceRefinementTests`)
- month-cache snapshot invalidation (`MonthAnalysisCacheInvalidationTests`)
- second-pass ranking refinement on larger thumbnails (`MonthAnalysisSecondPassRankingTests`)
- group-card ranking summary state mapping (`GroupCardRankingSummaryTests`)
- group-detail diagnostics copy (`GroupDetailDiagnosticsTests`)
- ranking behavior on mock inputs (`RankingServiceTests`)
- similarity preset thresholds + settings backward compatibility (`SimilarityPresetTests`)

## Build / Run

This repo includes `project.yml` for XcodeGen.

1. Install XcodeGen (if needed).
2. Run:

```bash
xcodegen generate
open KeepOne.xcodeproj
```

3. Build and run on iOS Simulator or device.
4. Ensure `NSPhotoLibraryUsageDescription` and `NSPhotoLibraryAddUsageDescription` are present (already included in `Info.plist`).

## Current MVP Simplifications

- Images only (videos ignored).
- No Live Photo special handling.
- No cross-month grouping.
- No background full-library analysis.
- No backend/cloud/account/subscription.
- No custom ML model.
- Conservative thresholds may miss borderline similar photos by design.

## Configurable Similarity Settings + Tracking File

- In month analysis, open similarity settings from the toolbar.
- You can set:
  - similarity preset (`Strict`, `Balanced`, `Relaxed`)
  - temporal gap (`10s` to `15m`, step `10s`)
  - cache validation mode (`Snapshot` or `Full Signature`)
- Applying a new value saves it and re-runs analysis for the current month.
- Values and change history are tracked locally in:
  - `Application Support/KeepOne/analysis-settings.json` (inside app sandbox).

## Next Improvements

1. Add batch operations across multiple selected months (still user-triggered).
2. Add test coverage for end-to-end month-analysis orchestration with mocks.
3. Add optional feature-level cache to speed up re-runs without changing behavior.
