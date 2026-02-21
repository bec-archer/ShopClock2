# ShopClock – Auto Time Tracker Spec

## Overview

A lightweight iOS app that automatically tracks when the user arrives at and leaves the workplace using geofencing, logs daily hours, and delivers a weekly summary every Monday morning at 8:00 AM with the option to text it to payroll.

---

## Core Requirements

### 1. Automatic Location-Based Clock In/Out

- Use **Core Location geofencing** to monitor the workplace location
- Define a geofence radius (~100 meters, adjustable in settings) around the workplace coordinates
- **Clock In:** Triggered automatically when the device enters the geofence
- **Clock Out:** Triggered automatically when the device exits the geofence
- Must work in the **background** — the app should not need to be open
- Log each clock-in and clock-out event with a timestamp
- Handle edge cases:
  - Brief exits (e.g., lunch run) — allow a configurable **grace period** (default: 15 min) before clocking out
  - Multiple entries/exits in a single day should be consolidated into total hours for that day
  - If the user is already inside the geofence when the app is first launched, prompt to clock in manually

### 2. Data Storage

- Use **SwiftData** for all local persistence
- **ClockEvent model:**
  - `id: UUID`
  - `clockIn: Date`
  - `clockOut: Date?` (nil if currently clocked in)
- **GapEntry model:**
  - `id: UUID`
  - `date: Date`
  - `exitTime: Date`
  - `returnTime: Date`
  - `duration: TimeInterval` (computed)
  - `isDeleted: Bool` (default `false` — when `true`, this gap is ignored and the time counts as working hours)
- When the user exits and re-enters the geofence mid-day, instead of creating separate clock events, the system should:
  1. Keep the original clock-in active
  2. Log the departure/return as a **GapEntry**
  3. Gaps marked as deleted are added back into the day's total hours
- **WeeklySummary (derived/computed):**
  - `weekStarting: Date` (Monday)
  - `totalHours: Double` (accounts for deleted gaps)
  - `dailyBreakdown: [DayEntry]` (day of week + hours)

### 3. Weekly Summary & Notification

- Every **Monday at 8:00 AM**, fire a local notification with the previous week's total hours
- Notification text example: `"Last week: 42.5 hrs. Want to text it to payroll?"`
- Tapping the notification opens the app to the weekly summary view with two actions:
  - **Text to Payroll** — opens a pre-composed message via `MFMessageComposeViewController` or the Messages URL scheme
  - **Dismiss** — just view the summary, no text sent
- The text message format should be simple and clean, e.g.:

```
Hours – Week of 2/10:
Mon: 8.5 hrs
Tue: 9.0 hrs
Wed: 8.0 hrs
Thu: 8.5 hrs
Fri: 7.5 hrs
Sat: 3.0 hrs
Total: 44.5 hrs
```

### 4. UI (Keep It Minimal)

- **Main View:** Current status (Clocked In / Clocked Out), today's running hours, clock-in time
- **Day Detail View:** Tap any day to see:
  - Total hours for that day (top)
  - A list of **gap cards** — each card shows the time you left, the time you returned, and the duration (e.g., "11:32 AM – 12:15 PM · 43 min")
  - Swipe a gap card to **delete** it (marks `isDeleted = true`) — the gap time gets added back to the day's total, hours recalculate instantly
  - Deleted gaps stay visible but grayed out with an "Undo" option in case of fat fingers
  - If no gaps exist for a day, show a clean "No gaps" state
- **Week View:** Simple daily breakdown for the current or any previous week, each day tappable → Day Detail View
- **History View:** Scrollable list of past weekly summaries
- **Settings View:**
  - Workplace location (set via map pin drop or current location)
  - Geofence radius (slider, 50m–300m)
  - Grace period before auto clock-out (slider, 5–60 min)
  - Payroll recipient phone number
  - Manual clock in/out override button

### 5. Manual Override

- Allow manual clock in/out from the main view (for days location isn't cooperating)
- Allow editing of clock in/out times for any day (tap the times in Day Detail View to adjust)
- Gap deletion is non-destructive — deleted gaps can always be restored via the Day Detail View

---

## Technical Notes

- **No Google services.** Apple-native only — Core Location, SwiftData, local notifications, Messages integration.
- **No cloud sync needed** (single device is fine unless specified otherwise later)
- **Background location:** Use `startMonitoring(for:)` region monitoring (low power, doesn't require always-on GPS). Request "Always" location permission with clear usage description.
- **Notification scheduling:** Use `UNUserNotificationCenter` to schedule repeating Monday 8 AM notification. Recalculate and update the notification content each Sunday night or on app launch.
- Target **iOS 17+** (SwiftData requirement)
- SwiftUI for all views

---

## Out of Scope (For Now)

- iCloud sync / multi-device
- Overtime calculations or pay rate math
- Export to CSV/PDF
- Multiple job locations
- Apple Watch companion

---

## Summary

Clock in when you arrive at the workplace. Clock out when you leave. Add it up. Get a summary Monday morning. Text it to payroll. That's it. 🔧
