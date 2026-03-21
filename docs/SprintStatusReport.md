# StreamCal — Sprint Status Report

**Sprint Period:** February 24 – March 1, 2026 *(Last demo)*  
**Report Updated:** March 14, 2026 *(Progress since last sprint demo)*  
**Team:** Luke Woods, Mireya, MJ

---

## Completed Sprint Goals (Original Sprint: Feb 24 – Mar 1)

The primary goal of that sprint was to establish the foundation for the StreamCal application in both development and design. On the development side, the core SwiftUI project was successfully created in Xcode, and the GitHub repository was initialized and connected. A scalable project architecture was established using a Model-View-ViewModel structure to support future growth. The initial Home screen scaffold and navigation structure were implemented, allowing the app to launch and function as a coded prototype.

On the design side, user research was conducted to better understand how users currently track streaming releases and identify major pain points. Based on these insights, initial wireframes were created in Figma to define the structure and layout of the core user experience. These designs focus on helping users easily see upcoming releases and navigate between shows.

Overall, that sprint successfully transitioned StreamCal from a concept into a functional coded prototype with a defined design direction.

---

## Progress Since Last Sprint Demo (Mar 2 – Mar 14, 2026)

### Custom Notifications — Major Focus

A full **custom notification system** has been built and integrated across the app. This is a core differentiator for StreamCal and directly addresses the user pain point of “missing new episodes.”

**What’s in place:**

- **NotificationService** (actor-based, Swift Concurrency): Central service for permission, scheduling, and cancellation.
- **Two notification types:**
  - **Air-date reminders:** When a new episode airs, users get a notification at **9:00 AM** that day (e.g. “S03E05 — Episode Title airs today”).
  - **Tonight’s plan reminders:** For episodes the user has explicitly **planned for today** in the Watch Planner, a reminder fires at **8:00 PM** (“Tonight: Show Name — You planned to watch S02E03 tonight.”).
- **Lifecycle integration:** Notifications are scheduled or updated when:
  - A show is added (TMDB import)
  - Episodes are refreshed from TMDB (on app launch and pull-to-refresh)
  - The user plans an episode for today (Calendar, Show Detail, Next Up)
  - A show’s episodes change (e.g. new season data)
- **Settings:** Dedicated Notifications section with permission status (authorized / denied / not determined), “Enable Episode Notifications” for first-time opt-in, and “Open Settings” for users who previously denied.
- **Launch flow:** The app requests notification permission on first launch and refreshes episode data + reschedules all notifications on every launch so reminders stay accurate after TMDB sync.

**Next steps for notifications (upcoming work):**

- Allow users to **customize times** (e.g. 9 AM vs 8 PM for air-date reminders).
- Optional **advance reminders** (e.g. “New episode in 24 hours”).
- Per-show notification toggles or quiet hours.

Building out and refining these **custom notifications** remains a priority for the next sprint.

---

### Data and Platform Research — Bringing More Data In

To support new features (calendar, “next up,” notifications, watch planning), the team has integrated a **first-party data pipeline** and documented a path for more data sources.

**Current data integration:**

- **TMDB (The Movie Database) API** is the primary external source:
  - **Search:** Users search by show name; results include poster, overview, first air date, rating.
  - **Show details:** Seasons list, episode counts, network, status (e.g. “Ended”, “Returning Series”).
  - **Season episodes:** Full episode list per season with titles and air dates.
  - **Full episode import:** When a user adds a show from search, the app fetches all seasons (excluding season 0 specials) and imports episodes with valid air dates into SwiftData.
- **RefreshService:** On each app launch (and on manual refresh), the app re-fetches episode data from TMDB for all tracked shows, **inserts new episodes** (e.g. new season), **updates air dates and titles** if TMDB changed them, then **reschedules all notifications**. This keeps the calendar and notifications in sync with real-world schedule changes.
- **SwiftData models** store: Show (title, platform, notes, TMDB id, poster, overview, status), Episode (season, episode, title, air date, watched, planned date). This supports Library, Calendar, Next Up, and Watch Planner without further external calls during normal use.

**Research and direction for more data:**

- **TMDB** is sufficient for **air dates, episode metadata, and show status**. Remaining gaps and options:
  - **Streaming availability (“where to watch”):** TMDB has some “watch provider” data; alternative or complementary sources include JustWatch-style APIs or partner feeds if available. **Next step:** Evaluate TMDB watch/providers endpoints and document response shape for “Watch on Netflix/Hulu” type features.
  - **Release schedules by region:** TMDB dates can vary by region. **Next step:** Confirm whether we use one primary region (e.g. US) or surface region in settings and how that affects notifications and calendar.
  - **New show discovery / “coming soon”:** TMDB supports trending, on-the-air, and similar endpoints. **Next step:** Prototype a “Discover” or “Coming Soon” view using these to drive future features (e.g. “Add to calendar” from discovery).
- **Stability and performance:** Rate limiting and error handling for TMDB are in place; token is kept server-side or in config (not hardcoded in public repo). **Next step:** Document a short “Data sources and roadmap” note (in repo or Notion) so design and dev stay aligned on what data we have and what we’re planning to add.

This **data and platform research** will continue so new features (e.g. “where to watch,” discovery, regional dates) can be added without re-architecting.

---

## Sprint Accomplishments and Current App Status

StreamCal is now a **feature-functional** SwiftUI app with:

- **Library:** Tracked shows with progress (next episode, backlog, “up to date through S02E05”), TMDB posters and metadata, archive support.
- **Calendar:** Monthly calendar with dots for days that have releases; tap a day to see episodes airing that day; plan an episode for “tonight” from the calendar.
- **Show detail:** Full episode list, watch/plan toggles, “next to watch” and backlog, refresh from TMDB, notification scheduling on plan changes.
- **Add Show:** TMDB search, add from results with full episode import.
- **Next Up:** Focused view for “next episode” across shows and quick plan/watch actions; scheduling notifications when planning for today.
- **Watch Planner / “Tonight’s Plan”:** Dedicated logic (WatchPlanner) for “tonight’s plan,” backlog, and progress labels; used by Library, Calendar, and Show Detail.
- **Settings:** About (version, show/episode counts), Notifications (permission status and enable/Open Settings), Data (Delete All with confirmation).
- **Persistence:** SwiftData for Show and Episode; background refresh and notification reschedule on launch.

The project has moved from a **structural prototype** to a **feature-functional prototype** with **custom notifications** and a **clear path for more data** to support upcoming features.

---

## Product Direction Decision (March 20, 2026)

**Core principle: low cognitive burden, high signal.**

StreamCal is a **smart TV guide**, not a task manager. The app's value is surfacing what's dropping from shows you follow — not asking users to track what they've watched, manage a backlog, or complete a checklist.

**What this means in practice:**
- **Notifications are the primary value driver.** The app does the work; the user just gets a push when a new episode drops. This is where build effort should focus.
- **Views are forward-only.** No backlog sections, no “Unwatched” guilt-pills, no past-episode tracking in primary UI. The Schedule tab (formerly Calendar) shows today + the next 60 days only.
- **”Mark watched” is a light dismissal**, not a mandatory task. It tells the app what's new for the user, but it should feel effortless — one swipe — not a chore.
- **No catch-up / binge-tracking UX.** The app is for following active shows. Users who want to binge a back catalog have other tools; StreamCal shouldn't become a half-hearted Trakt clone.

**Tab purposes under this direction:**
| Tab | Purpose |
|---|---|
| Library | Your shows — add, archive, see what's coming next per show |
| Next Up | Episodes dropping today or soon from shows you follow |
| Schedule | Forward-looking release calendar — what's dropping this month |
| Settings | Notification preferences — the primary control surface |

---

## Upcoming Sprint Goals (Next Sprint: March 15 – March 22, 2026)

- **Custom notifications (emphasis):** Implement user-configurable reminder times, optional advance reminders (e.g. 24 hours before), and per-show notification toggles.
- **Forward-only views:** Remove backlog/past-episode UI from Schedule and Next Up; Schedule tab becomes a clean forward-only release calendar.
- **Data and features:** Use TMDB watch-provider data to explore “where to watch” or similar; document data roadmap and region strategy.

---

## Team Member Stand-Up Reports

### Luke Woods — Product Designer and Developer

This period, Luke implemented the **custom notification system** (NotificationService with air-date and “tonight” reminders, permission flow, and scheduling across add/refresh/plan flows). He integrated **TMDB** for search, show details, and full episode import, and added **RefreshService** to sync episodes on launch and reschedule notifications. He built the **Watch Planner** (tonight’s plan, backlog, progress labels), Calendar with release dots and day detail, Library with progress, Show Detail, Next Up, and Settings (including Notifications). The app now has an end-to-end flow: add show from TMDB → episodes and calendar → plan/watch → notifications. **Next:** Customizable notification times and advance reminders; document data roadmap and explore watch-provider/“where to watch” data.

### Mireya — UX Designer and User Research

*(Unchanged from last report; update as needed.)*

This sprint, Mireya conducted user research to understand how users currently track streaming releases and identified key pain points. Based on these findings, she created initial wireframes in Figma for the Home screen and Calendar view. She is refining layouts, navigation flow, and information hierarchy. Design work is on track. **Next:** Align Figma with new notification and Watch Planner flows; support usability testing.

### MJ — UX Designer

*(Unchanged from last report; update as needed.)*

This sprint, MJ contributed to user research and helped translate insights into design concepts. He developed Figma wireframes for the Calendar view and show browsing experience. He is finalizing wireframes and ensuring consistency across screens to guide development and usability testing. No blockers. **Next:** Consistency with new notification and data-driven flows.

---

## Summary

The last sprint established StreamCal’s technical and design foundations. **Since the last sprint demo,** the app has gained a **full custom notification experience** (air-date and “tonight’s plan” reminders, permission and Settings), **TMDB-backed data** (search, import, refresh, episode sync), and **Watch Planner–driven views** (Library, Calendar, Show Detail, Next Up). **Emphasis for the next sprint:** expand **custom notifications** (configurable times, advance reminders, per-show options) and continue **data and platform research** (watch providers, discovery, region strategy) so new features can be built on a clear data roadmap. The project is on track and ready for the next phase of notification and data work.
