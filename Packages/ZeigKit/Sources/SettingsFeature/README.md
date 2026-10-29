# SettingsFeature

The Settings sheet, laid out like Filz!'s: a Form in its own NavigationStack with a close
button at the top right.

| View | Content |
|---|---|
| `SettingsView` | Creating Archives (default format, level), Experimental (test RAR backend with a confirmation and warnings; "use it for opening RAR too"), Help (Format Guide), About (app, 7-Zip, libarchive and rars versions, and the pages below). |
| `BackendsView` | Each engine's role and version, and who opens and creates each format right now. |
| `DeveloperSection`, `FontLabView` | Developer mode (seven taps on the App version): the console sheet, its picture-in-picture window, native output capture, exporting, sharing and clearing the log, and the Font Lab. |
| `AboutAppView`, `PrivacyPolicyView`, `OpenSourceView` | About (Filz!'s layout; the logo is `AppLogo` in Resources/Media.xcassets, a placeholder), privacy (no data collected, no network), and every bundled component with its license. |
| `AppInfo` | Name, version, copyright, and `sourceURL` (set it when the repository is public). |

When a native library is updated, update its version in `OpenSourceView`.
