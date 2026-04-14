# StreamCal — Claude Code Instructions

## Project
SwiftUI iOS app for tracking TV shows, movies, anime, and sports. Built with SwiftData, no third-party dependencies except RevenueCat (via SPM).

Xcode project: `StreamCal.xcodeproj`  
All source files: `StreamCal/`

## Build & Run

```bash
# Build
xcodebuild -project StreamCal.xcodeproj -scheme StreamCal \
  -destination 'id=8D616F16-C24D-4D69-938E-20A47A6DA4B9' build 2>&1 | tail -10

# Install + launch on the booted simulator
xcrun simctl install <BOOTED_ID> \
  ~/Library/Developer/Xcode/DerivedData/StreamCal-eruyelggrgnpkbggqvleztjirfoy/Build/Products/Debug-iphonesimulator/StreamCal.app
xcrun simctl launch <BOOTED_ID> com.lukewoods.StreamCal
```

Check which simulator is booted before building:
```bash
xcrun simctl list devices | grep Booted
```

Primary test device: **iPhone 17** (`8D616F16-C24D-4D69-938E-20A47A6DA4B9`)

## Architecture

### Data layer
- **SwiftData** — `Show`, `Episode`, `Movie`, `SportTeam`, `Game`, `AnimeShow` models
- `Show` cascade-deletes its `Episode` children
- No migrations needed for adding optional/defaulted properties — SwiftData handles them automatically
- `@Query` in views; `modelContext` injected via environment

### Services
| File | Purpose |
|---|---|
| `TMDBService.swift` | TMDB API — search shows/movies, fetch details, seasons, watch providers |
| `ESPNService.swift` | ESPN API — team search across 14 leagues, schedule fetch (seasontype=2 regular + seasontype=3 playoffs) |
| `AniListService.swift` | AniList GraphQL — anime search and episode data |
| `TheSportsDBService.swift` | TheSportsDB fallback for sports teams |
| `TraktService.swift` | Trakt OAuth — sync watch history |
| `ClaudeService.swift` | Cloudflare Worker proxy to Claude API — structured JSON responses |
| `NotificationService.swift` | Actor — schedules air-date and plan notifications |
| `RefreshService.swift` | Runs on launch and pull-to-refresh — re-fetches TMDB/ESPN, updates episodes |
| `PurchaseService.swift` | RevenueCat — Pro entitlement, paywall |
| `WatchPlanner.swift` | Stateless helpers — plan tonight/tomorrow/weekend, backlog, progress |

### AI (ClaudeService + AskStreamCalView)
- Calls `streamcal-ai.lukewoodstech.workers.dev/ai` (Cloudflare Worker holds the API key)
- Request body: `{ "prompt": "...", "customerID": "..." }`
- Claude returns a JSON object (sometimes wrapped in ` ```json ` fences — strip them before decoding)
- Structured response shape: `StreamCalResponse { summary, sections[{ type, heading, items[{ title, detail, badge, badgeStyle, isInLibrary }] }] }`
- Section types: `live_now`, `airing_tonight`, `coming_next`, `recommendations`, `answer`
- Discovery cards: items with `isInLibrary == false` (or nil) get TMDB poster cards; tapping poster opens detail sheet, tapping `+` badge adds directly

### UI
- `FloatingTabBar` — custom SwiftUI tab bar (not native UITabBar — use `app.buttons["Label"]` in UI tests, not `app.tabBars`)
- `DesignSystem.swift` — shared colors (`DS.Color.*`), radii (`DS.Radius.*`), fonts
- `StreamCalBrand.swift` — app name, accent color constants
- `CachedAsyncImage.swift` — lightweight async image with in-memory cache

## Key Conventions
- **No SwiftUI previews** — test by building and running on simulator
- **Silent failure on AI** — all `ClaudeService` methods return `nil` on failure, never throw to the UI
- **isInLibrary nil = not in library** — when Claude omits the field, treat as not in library
- **ESPN schedules** — always fetch both `seasontype=2` and `seasontype=3` and merge; omitting the param returns 0 events
- **RevenueCat customerID** — obtained via `PurchaseService.shared.customerID` (calls `Purchases.shared.appUserID`)
- Prefer editing existing files over creating new ones
- Don't add comments unless logic is non-obvious

## Add Sheets — Library Deduplication
All three add sheets (`AddShowSheet`, `AddMovieSheet`, `AddTeamSheet`) filter out items already in the library from search results and suggestions — they should never appear in results at all, not even dimmed.

## GitHub
Remote: `https://github.com/lukewoodstech/StreamCal.git`  
Branch: `main`
