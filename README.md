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
- `GroupDetailView` highlights the suggestion, supports manual multi-select deletion, and asks for confirmation.

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
  - tracks temporal-gap change history in the same file
- `MonthAnalysisService`:
  - orchestrates month-only analysis pipeline
  - loads persisted temporal gap at startup
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
6. `MonthAnalysisService`:
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

- Base thresholds:
  - Vision feature-print distance (`default: 13`)
  - dHash normalized Hamming distance (`default: 0.26`)
- Thresholds are relaxed by temporal proximity (closer-in-time pairs allow more variation).
- Extra tolerance is applied when both photos likely contain the same subject:
  - both include faces
  - face count is close
  - face area ratio is close
- Mixed cases (face vs no-face) and no-face pairs are evaluated with stricter caps.
- Pairwise graph edges are limited to close capture times (`<= 180s`) unless same burst id.
- Very large visual distances are still rejected to avoid clear false positives.
- Matching remains sequence-scoped only (month + user-selected time gap), never whole-library.

## Ranking Strategy (Suggestion, Not Guarantee)

`RankingService` computes an explainable heuristic score per photo with signals inspired by Apple’s published high-level direction (multi-signal curation, not a single metric):
- face clarity (count, prominence, centering)
- sharpness proxy (thumbnail gradients)
- composition prominence (saliency + centering)
- exposure balance (brightness + contrast)
- resolution signal
- burst auto-pick bonus (when present)
- favorite bonus
- screenshot penalty

The top score becomes `suggestedBestAssetID`. UI labels it as a suggestion only.

Apple has not publicly documented an exact Featured-Photo/Key-Photo formula, so this MVP uses a transparent on-device approximation.

## Caching Approach

- Cache is local JSON by month key (`YYYY-MM`).
- Opening an already analyzed month returns cache quickly.
- “Re-Run” forces fresh month analysis and rewrites cache.
- If similarity settings differ from the cached run config, cache is skipped and analysis recomputes.

### Current Cache Limitations (MVP)
- Cache invalidation is basic: no automatic diffing of library changes.
- If user edits/removes photos outside app, cache may become stale until re-run.
- Cache stores final grouped/ranked output only (no feature-level cache).

## Unit Tests (Lightweight)

Included tests cover:
- temporal segmentation (`TemporalSegmentationTests`)
- connected-components graph grouping (`GraphGroupingTests`)
- ranking behavior on mock inputs (`RankingServiceTests`)

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

## Configurable Time Gap + Tracking File

- In month analysis, use `Adjust` (or toolbar `Gap`) to change the temporal similarity gap.
- Range: `10s` to `15m`, step `10s`.
- Applying a new value saves it and re-runs analysis for the current month.
- The value and change history are tracked locally in:
  - `Application Support/KeepOne/analysis-settings.json` (inside app sandbox).

## Next Improvements

1. Add stronger cache invalidation (month asset signature + delta checks).
2. Add richer quality signals (eyes open, expression quality, saliency).
3. Add presets for strict/balanced/relaxed similarity settings.
4. Add batch operations across multiple selected months (still user-triggered).
5. Add iCloud-not-local handling improvements and clearer state messages.
6. Add test coverage for end-to-end month-analysis orchestration with mocks.
