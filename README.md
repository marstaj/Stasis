# Stasis

Menu bar utility to pause (`SIGSTOP`) and resume (`SIGCONT`) running macOS apps, and to
recover apps that macOS itself paused under memory pressure.

Each app row shows its memory footprint and CPU rate; expand a row to see and toggle the
individual processes (browser renderers, JVMs, helpers). Pause state is read from the kernel
process table, so system-initiated pauses show up without the tool having been involved.

Pausing frees CPU, not RAM. A paused app keeps its memory until the compressor or swap takes it.

## Build and run

Requires macOS 14+. `make test` and `make build` need only the Xcode command line tools
(Swift 6); `make run` and `make install` need full Xcode 26+ because the app icon is compiled
from an Icon Composer document with `actool`.

```
make test      # unit tests for the grouping / state / signal logic
make run       # build release, assemble build/Stasis.app, launch it
make install   # same, then copy to /Applications and launch
```

The `.app` wrapper is assembled by the Makefile from `Info.plist` and the compiled
`Resources/AppIcon.icon`, then ad-hoc signed; there is no Xcode project. `swift run` works for quick iteration but shows a Dock icon and cannot
register launch-at-login, since both need the bundle.

## Notes

- Finder, Dock and Stasis itself are hidden from the list.
- Processes of other users cannot be signalled without root; the footer shows the error.
- Sampling: every 2 s while the popover is open, every 30 s otherwise (keeps the menu bar icon
  in sync when the system pauses something).
