# Stasis

Menu bar utility to pause (`SIGSTOP`) and resume (`SIGCONT`) running macOS apps, and to
recover apps that macOS itself paused under memory pressure.

<p align="center">
  <img src="docs/screenshot.png" width="410" alt="The Stasis popover listing running and paused apps">
</p>

Each app row shows its memory footprint and CPU rate; expand a row to see and toggle the
individual processes (browser renderers, JVMs, helpers). Pause state is read from the kernel
process table, so system-initiated pauses show up without the tool having been involved.
The control at the top sorts the list by name, memory or CPU; the choice is remembered.

Below it, Pause All Except <app> pauses every app but the one in front, which it names; Pause
All pauses that one too; Resume All resumes everything paused. All three are also in the menu
bar icon's right-click menu, together with Quit.

The ✕ at the end of a row kills the app or process with `SIGKILL` (paused processes ignore
anything gentler). It takes two clicks: the first arms it, moving the pointer away disarms it.

Pausing frees CPU, not RAM. A paused app keeps its memory until the compressor or swap takes it.

## Install

Download `Stasis.zip` from the [latest release](https://github.com/marstaj/Stasis/releases/latest),
unzip it and move `Stasis.app` to `/Applications`. It runs on Apple silicon and Intel, macOS 14+.

The app is not notarized, so nothing on your Mac checks where the zip came from. To check it
yourself before opening it, verify with the [GitHub CLI](https://cli.github.com) that it was
built by this repository's release workflow:

```
gh attestation verify Stasis.zip --repo marstaj/Stasis
```

macOS refuses the first launch for the same reason. Click Done on that dialog, then open System
Settings > Privacy & Security, scroll to the bottom and click Open Anyway; the button is only
there for about an hour after a refused launch.

Or clear the quarantine flag on the zip before unzipping it. If the terminal answers "Operation
not permitted", macOS is not letting it do that; use Open Anyway instead.

```
xattr -d com.apple.quarantine ~/Downloads/Stasis.zip
```

Building it yourself with `make install` (see below) needs neither step.

The `stasis` command is inside the bundle; to put it on your path:

```
ln -s /Applications/Stasis.app/Contents/Helpers/stasis /opt/homebrew/bin/stasis
```

## Build and run

Requires macOS 14+. `make test` and `make build` need only the Xcode command line tools
(Swift 6); `make run`, `make install` and `make release` need full Xcode 26+ because the app
icon is compiled from an Icon Composer document with `actool`.

```
make test      # unit tests for the grouping / state / signal / matching / sorting / CPU / version logic
make run       # build release, assemble build/Stasis.app, launch it
make install   # same, then copy to /Applications, symlink the CLI, launch
make raycast   # npm install + register the Raycast extension (see below)
make release   # universal build zipped to build/Stasis.zip (see Releasing)
```

The `.app` wrapper is assembled by the Makefile from `Info.plist`, the compiled
`Resources/AppIcon.icon` and the menu bar icons (`Resources/MenuBar*.svg`), then ad-hoc signed;
there is no Xcode project. `swift run Stasis` works for quick iteration but shows a Dock icon,
falls back to an SF Symbol in the menu bar and cannot register launch-at-login, since all three
need the bundle.

## Command line

The bundle carries a CLI at `Stasis.app/Contents/Helpers/stasis`; `make install` symlinks it to
`/opt/homebrew/bin/stasis` (override with `BIN=`). It works whether or not the menu bar app is
running and pokes the app to refresh its icon after a change.

```
stasis list [--json] [--processes]      apps with state and memory; JSON is what Raycast reads
stasis pause <app> / resume <app>       pid, bundle id or name, case-insensitive; a partial name
                                        needs 3+ characters and must match exactly one app
stasis kill <app>                       SIGKILL to the app and its processes, no confirmation
stasis pause-all [--include-frontmost]  spares the app in front unless told otherwise
stasis resume-all
```

Exit status: 1 usage, 2 no or ambiguous app (candidates on stderr), 3 some signal failed.

## Raycast

`raycast/` is a Raycast extension with four commands: Pause / Resume Apps (every app with
memory and state, Enter pauses a running app or resumes a paused one, the row stays put), Pause
All Except Front App, Pause All Apps and Resume All Apps, which are also actions inside the first. The list also has a Kill
action (⌃X) that asks before it kills. It shells out to the CLI at its
bundle path, so Stasis must be installed in `/Applications`. Needs Node; `make raycast` installs
the npm dependencies and starts Raycast's dev server, which registers the extension. Stop the
server once the commands appear in Raycast, they stay registered. Re-run it after changing the
extension's source.

## Notes

- Finder, Dock, Raycast and Stasis itself are hidden from the list. Raycast because a paused
  launcher could not run the resume command.
- Processes of other users cannot be signalled without root; the footer shows the error.
- Sampling: every 2 s while the popover is open, every 30 s otherwise (keeps the menu bar icon
  in sync when the system pauses something).
- At launch and once a day the app asks the GitHub API for the latest release and, if it is
  newer, links to it at the bottom of the popover. Nothing else leaves the machine.

## Releasing

Pushing a three-part tag like `v1.2.3` runs `.github/workflows/release.yml`: it runs the tests,
builds a universal app stamped with that version, attests the zip's build provenance and attaches
`Stasis.zip` to a new GitHub release. Local builds are stamped with the latest tag in the checkout.

```
git tag v1.2.3 && git push origin v1.2.3
```

Or let the workflow pick the version: on GitHub open Actions > Release > Run workflow and choose
which part to raise (patch, minor or major). It releases the head of `main` as the next version
after the latest release tag; the tag is created with the release, so a failed run leaves none.

The build is ad-hoc signed. To notarize it instead, so it opens without the Gatekeeper step:

1. Join the Apple Developer Program and create a Developer ID Application certificate.
2. Export the certificate as a `.p12` and add it, base64 encoded, with its password as
   repository secrets. Add an App Store Connect API key (key, key id, issuer id) the same way.
3. In the workflow, import the certificate into a temporary keychain before `make release`.
4. In the Makefile, replace `--sign -` with `--sign "Developer ID Application: <name> (<team>)"
   --options runtime --timestamp` in both `codesign` calls.
5. After `make release`, run `xcrun notarytool submit build/Stasis.zip --wait` with the API key,
   then `xcrun stapler staple build/Stasis.app` and zip the app again with the `ditto` command
   from the Makefile, so the release carries the stapled ticket.
6. In Install, drop the Open Anyway / `xattr` paragraph and the "not notarized" wording around
   the verify step.

## License

[Apache-2.0](LICENSE). The Raycast extension in `raycast/` is [MIT](raycast/LICENSE), the only
license Raycast accepts for extensions.
