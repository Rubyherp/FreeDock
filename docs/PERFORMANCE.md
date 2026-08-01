# Performance auditing

FreeDock exposes privacy-safe Points of Interest for its user-visible hot paths:

- `DockRestore` — rebuilding the active profile's dock windows
- `MenuRebuild` — recreating the menu-bar menu and preferences snapshot
- `WindowDiscovery` — finding an application's windows across Spaces and displays
- `WindowThumbnail` — loading one window preview image, including cache lookup
- `ConfigSave` — encoding, backup rotation, and atomic configuration writing

These intervals contain no application names, window titles, file paths, or other user data. Record the FreeDock process with Instruments' **Points of Interest** template, then perform the interaction under investigation. Compare warm and cold runs separately because window thumbnails use a short-lived cache.

The menu refresh path deliberately keeps global shortcut registrations intact unless their settings change. This avoids unregistering and registering Carbon hot keys during unrelated dock, menu, or running-app updates.

For a repeatable regression check before release, run:

```sh
make test-reliability
```

Then profile a dock restore, a menu open, and one cold followed by one warm window-preview session. Investigate regressions relative to the previous release rather than relying on machine-specific absolute timings.
