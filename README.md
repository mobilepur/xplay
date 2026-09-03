# XPlay

Grundgerüst einer macOS-Menüleisten-App zum Bauen und Starten von Xcode-Projekten.
Die Menüleiste zeigt ein Play-Symbol und während eines Builds einen animierten
Spinner.

Aktuell ist noch kein Projekt konfiguriert. Deshalb ist der Play-Button zunächst
deaktiviert. Projekte und Schemes sollen im nächsten Schritt über die App verwaltet
und ausgewählt werden.

## Projekt erzeugen

```sh
xcodegen generate
open XPlay.xcodeproj
```

## Testen

```sh
xcodebuild test \
  -project XPlay.xcodeproj \
  -scheme XPlay \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/XPlayDerivedData
```
