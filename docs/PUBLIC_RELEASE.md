# Going public: what is done and what only the owner can do

TerminalAsset has no server of its own. Everything it stores lives on the device, so "backend for public" means
the pieces the App Store and users expect around that: privacy, data control, and honest behaviour.

## Done in the repo

| Area | State |
| --- | --- |
| Data stays on device | Calendar, notes, links, tasks and files are stored locally (SwiftData + App Group). |
| Privacy manifest | `App/PrivacyInfo.xcprivacy`: no tracking, coarse location (weather) as app functionality, UserDefaults reason `CA92.1`. |
| Export | Settings → Export my data saves notes, links, tasks and file names as JSON through Save to Files. |
| Delete | Settings → Delete all data erases the database, imported files and the share queue (calendar untouched). |
| Privacy page | Settings → How your data is used states what stays on the device and what leaves it. Kept in sync with the code. |
| Coarse location | Forecast and city-name lookup both use a position rounded to ~1 km. |
| Encryption export flag | `ITSAppUsesNonExemptEncryption = false` (only standard HTTPS is used). |
| No fake UI | Controls for features that do not exist yet (Pro, background prep, iCloud, decay, hybrid AI) were removed. |
| Add events | Calendar tab "+": New Event form (all-day, repeat, calendar picker) and a Quick add sentence field (Thai and English, parsed on the device). |
| Prep reminders | Opt-in local notifications ~15 minutes before an event with open tasks or nothing attached. No push service, no network. |
| Widget | Up Next home-screen (small, medium) and lock-screen widget, fed by a snapshot file in the App Group. |
| Deep links | A tapped reminder or widget opens the event (`terminalasset://event?key=...`, strict parser). |
| Find Context | Siri / Shortcuts action ("Find context in TerminalAsset") that opens Search with the words filled in. |
| Edit and preview | Edit notes, tasks and links (leading swipe); attached files open in Quick Look; "Open in Calendar" hands an event to Apple Calendar. |
| Accessibility | Checked with CI screenshots at the largest text size and in dark mode; fixed-size grids and tiles cap their text, rows stack or wrap. |
| Thai | String catalogs (app, widget, share extension, permission prompts) with Thai plurals; CI captures the main screens in Thai. |

## Only the owner can do these

1. **Apple Developer Program** membership, then in App Store Connect: create the app record, the bundle IDs
   `com.terminalasset.app`, `com.terminalasset.app.share` and `com.terminalasset.app.widget`, and the App Group
   `group.com.terminalasset.app` (all three targets use it).
2. **Signing**: set the team in Xcode (or CI secrets). CI builds with `CODE_SIGNING_ALLOWED=NO`, so it cannot
   produce an installable build.
3. **Privacy policy URL** and **support URL**: App Store Connect requires both. The policy must say what
   Settings → How your data is used says.
4. **App Privacy answers** in App Store Connect: they must match `PrivacyInfo.xcprivacy`
   (Coarse Location, not linked to the user, not used for tracking, app functionality).
5. **Store listing**: name, subtitle, description, keywords, screenshots (CI already produces simulator
   screenshots in `screenshots/`), age rating, category.
6. **Test on a real iPhone**: EventKit writes, the Share Extension, notification delivery and the widget only run for
   real on a device. CI uses a stub calendar and a stub notification scheduler, so adding events to a real calendar
   (iCloud, Google, Exchange), tapping a real reminder, and the widget on a real home screen have not been exercised.
7. **Review the Thai wording** with a native reader before release (`App/Localizable.xcstrings`, `th` column). It was
   written by the assistant and has not been proofread. Strings that come from calendar data or sample content stay as
   they are.

## Not built yet (and therefore not offered in the app)

- **Cloud AI** (Firebase AI Logic + App Check). Needs a Firebase project, `GoogleService-Info.plist`, and App Check
  configured with App Attest. Nothing in the app calls a cloud model today. When it exists, each use must show
  what is sent and why, and ask first.
- **Pro plan / StoreKit 2**: add only once there is a Pro feature to sell. Products must be created in App Store
  Connect.
- **Context decay, iCloud cold storage, background prep**: designed in `CLAUDE.md`, not implemented.
