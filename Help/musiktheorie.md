---
id: musiktheorie
title: Akkorde und Musiktheorie
summary: Akkorde entwerfen, Tonleitern untersuchen und Folgen für eine Szene planen.
order: 25
keywords: [Akkord, Tonleiter, Quintenzirkel, Voicing, Arrangement]
---

Jede Szene besitzt einen Grundton und eine Tonleiter. Wähle beides oberhalb des Arbeitsbereichs. Eine Spur verwendet standardmäßig **Wie Szene**; im Bereich **Spuren** kannst du ihr für Experimente eine eigene Tonleiter zuweisen.

## Akkordlabor

Wähle Grundton und Akkordtyp. Das Labor zeigt Symbol, Akkordtöne, Intervalle, harmonische Stufe und leiterfremde Töne. **Umkehrung ↑** und **Umkehrung ↓** verändern die Lage. Ziehe einen Notenkopf im Notenfeld vertikal, um das konkrete Voicing chromatisch zu verändern.

Der Bereich **In Szene übernehmen** nennt die resultierende Position ausdrücklich. In einer leeren Szene wird der Akkord zum ersten Akkord ab Takt 1. Bei einer bestehenden Folge kannst du ihn am Ende anfügen, unmittelbar vor einem vorhandenen Akkord einfügen oder einen vorhandenen Akkord ersetzen. Positionen zeigen Akkordsymbol und Takt; nach der Aktion bestätigt Chordflow das Ergebnis. Beim Ersetzen bleiben Position und Dauer erhalten. Symbol und konkrete Tonhöhen werden gemeinsam gespeichert. Mit **Auf Tonleiter einrasten** landet ein gezogener Ton automatisch auf dem nächsten Ton der Szenentonleiter.

Das Akkordlabor spielt das aktuelle Voicing nach jeder Änderung kurz mit dem internen Pianoklang. Schalte **Nach Änderungen automatisch spielen** aus, wenn du still arbeiten möchtest. **Probehören** spielt den Akkord jederzeit manuell; dafür ist kein MIDI-Keyboard erforderlich.

Die Notationskarte verwendet denselben ABC-/abcjs-Renderer wie die vollständige Partitur. Schlüssel, Vorzeichen, Notenköpfe und Hilfslinien werden deshalb in beiden Ansichten identisch berechnet und gesetzt. Tiefe Voicings verwenden den Bassschlüssel, höhere den Violinschlüssel. Ziehe die Tonkarten unterhalb der Notation vertikal, um das Voicing mit der Maus zu verändern; die gemeinsame Partiturkomponente wird anschließend unmittelbar neu gerendert. Wiederholte Umkehrungen bleiben innerhalb des darstellbaren musikalischen Registers.

## Arrangement

Jede Karte ist ein Akkordereignis der Szene. Ziehe eine Karte auf eine andere, um die Reihenfolge zu verändern. Die Zahl der Zählzeiten bestimmt die Länge. Akkord- und Bassspur sowie die Partiturvorschau werden unmittelbar aus der Folge erzeugt; die Bassspur spielt dabei die jeweiligen Grundtöne.

## Quintenzirkel

Der äußere Name bezeichnet die Durtonart, der kleinere innere Name ihre parallele Molltonart. Ein Klick setzt das tonale Zentrum der Szene. Die App zeigt dazu Tonleiter, Dominante, Subdominante und Paralleltonart.

Nach einem Klick entscheidest du ausdrücklich zwischen **Nur Analyse ändern** und **Akkordfolge transponieren**. Die kontrollierte Transposition verschiebt gespeicherte Akkorde, Voicings und die daraus erzeugte Bassspur. Frei eingegebene Melodien bleiben unverändert.
