# Chordflow

Chordflow ist eine eigenständige macOS-App für ABC-Partituren und MIDI-Keyboards.

## Funktionen

- Partituren für Live-Sets in einer linken Seitenleiste verwalten
- Szenen mit Tempo und den Spuren Bass, Melodie und Akkorde bearbeiten
- komplette Partitur oder einzelne Takte abspielen
- Noten und Akkorde direkt anklicken
- angeschlossenes MIDI-Keyboard durch Klick auf die Partitur aktivieren
- gespielte MIDI-Noten hören, benennen und in der Partitur hervorheben
- Partitur als MIDI-Datei exportieren
- Partituren, Szenen und Spuren automatisch in SQLite speichern
- integrierte Markdown-Hilfe über `Hilfe → App-Hilfe` oder `⌘?`

## Starten

```bash
swift run Chordflow
```

Alternativ lässt sich `Package.swift` direkt in Xcode öffnen und das Scheme `Chordflow` starten.

## Installieren

Der zentrale Installer baut, signiert und installiert Chordflow nach `/Applications`:

```bash
pwsh /Users/thomassalomon/dev-swift/_scripts/Install-App.ps1 Chordflow arm
```

## Datenspeicher

Chordflow speichert die Bibliothek unter `~/Library/Application Support/Chordflow/scores.sqlite3`. Neue Partituren enthalten eine erste Szene mit 120 BPM und die drei vorbereiteten Spuren **Bass**, **Melodie** und **Akkorde**. Weitere Szenen erhalten dieselbe Grundstruktur.

Beschädigte oder strukturell ungültige Daten werden sichtbar abgelehnt und protokolliert.
