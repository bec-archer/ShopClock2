# ShopClock

A lightweight iOS app that auto-tracks work hours using geofencing. Clock in when you arrive, clock out when you leave — automatically.

## Features

- **Automatic clock in/out via geofencing** — uses Core Location region monitoring to detect arrivals and departures
- **Background operation** — works without the app being open
- **Grace period for brief exits** — configurable delay (5–60 min) prevents false clock-outs for lunch runs, etc.
- **Gap tracking with swipe-to-delete** — mid-day departures are logged as gaps; swipe to remove a gap and add that time back to your total
- **Weekly Monday summary notification** — fires every Monday at 8 AM with last week's total hours
- **Text-to-payroll one-tap SMS** — send your weekly hours to a saved phone number via Messages
- **Manual override** — clock in/out manually when location isn't cooperating; edit times after the fact
- **History view** — browse past weekly summaries with daily breakdowns and bar charts

## Requirements

- iOS 17+
- Xcode 15+
- Physical device (geofencing does not work in the simulator)
- "Always" location permission

## Setup

1. Open `ShopClock.xcodeproj` in Xcode
2. Update the bundle identifier and development team in Signing & Capabilities
3. Build and run on a physical device
4. Grant "Always" location permission when prompted
5. Open Settings in the app and set your workplace location (pin drop or current location)
6. Optionally add a payroll recipient phone number for weekly SMS summaries

## Architecture

All Apple-native. No cloud services, no third-party dependencies.

- **SwiftUI** — all views
- **SwiftData** — local persistence (ClockEvent, GapEntry models)
- **Core Location** — geofence region monitoring
- **UserNotifications** — weekly Monday 8 AM summary
- **BackgroundTasks** — Sunday night refresh to update notification content

## Project Structure

```
ShopClock/
  ShopClockApp.swift          # App entry point, setup, notification delegate
  Managers/
    ClockManager.swift         # Clock in/out logic, grace periods, weekly summaries
    LocationManager.swift      # Geofence monitoring, region enter/exit
    NotificationManager.swift  # Weekly notification scheduling, background refresh
  Models/
    ClockEvent.swift           # SwiftData model for clock in/out events
    GapEntry.swift             # SwiftData model for mid-day gaps
  Views/
    MainView.swift             # Status, today's hours, navigation
    WeekView.swift             # Daily breakdown with bar chart, text-to-payroll
    DayDetailView.swift        # Gap cards, time editing, manual entry
    HistoryView.swift          # Past weekly summaries
    SettingsView.swift         # Workplace location, geofence radius, grace period
  Utilities/
    DateExtensions.swift       # Date/Double formatting helpers
```

## License

Provided as-is for personal use.
