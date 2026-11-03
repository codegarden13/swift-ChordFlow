---
title: MIDI und Speicherung
summary: Ein Keyboard verwenden, Partituren automatisch speichern und MIDI exportieren.
order: 30
keywords: [MIDI, Keyboard, Export, Datei]
---

Schließe das MIDI-Keyboard an und klicke die Partitur an. Chordflow ordnet das Keyboard diesem Dokument zu, gibt eingehende Noten wieder und hebt passende Noten in der Partitur hervor. Bei mehreren geöffneten Dokumenten erhält immer die zuletzt angeklickte Partitur die Eingabe.

Wird kein Keyboard erkannt, prüfe Kabel, Stromversorgung und die MIDI-Verbindung. **MIDI erneut suchen** startet anschließend eine neue Erkennung. Ein technischer Fehler wird mit seiner Ursache sichtbar angezeigt und protokolliert.

**MIDI exportieren** erzeugt aus dem aktuellen Abschnitt eine `.mid`-Datei. Die bearbeitbaren Partituren, Abschnitte und Spuren speichert Chordflow automatisch in seiner SQLite-Datenbank; separate Set-Dateien sind nicht erforderlich.
