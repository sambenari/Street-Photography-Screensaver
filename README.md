# Street Photography Screen Saver

Native macOS screen saver bundle that displays photos from a local cache of the Photos album named `Street Photography`.

macOS does not reliably grant Photos access to the legacy screen saver host, so the project includes `Street Photography Sync.app`. That app owns the Photos permission prompt, exports the album to `~/Library/Screen Savers/Street Photography Cache`, embeds that cache into the installed `.saver` bundle, and re-signs it.

## Build

```sh
make
```

The compiled bundle is written to `/private/tmp/StreetPhotographySaverBuild` so macOS code signing is not polluted by File Provider metadata from the Documents folder.

## Install

```sh
make install
```

The bundle installs to `~/Library/Screen Savers/Street Photography.saver`, where macOS can load it from System Settings.

The sync app installs to `/Applications/Street Photography Sync.app`.

## Sync Photos

Open `/Applications/Street Photography Sync.app`, allow Photos access, and wait for it to report that photos were synced and embedded.

If access was previously denied, enable it in System Settings > Privacy & Security > Photos for `Street Photography Sync`, then reopen the app.

## Verify

```sh
make verify
```

This checks that the screen saver bundle loads and instantiates as a native `ScreenSaverView`.
