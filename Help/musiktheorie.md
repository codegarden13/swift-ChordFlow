---
title: Akkorde und Musiktheorie
summary: Akkorde entwerfen, Tonleitern untersuchen und Folgen für eine Szene planen.
order: 25
keywords: [Akkord, Tonleiter, Quintenzirkel, Voicing, Arrangement]
---

Jede Szene besitzt einen Grundton und eine Tonleiter. Wähle beides oberhalb des Arbeitsbereichs. Eine Spur verwendet standardmäßig **Wie Szene**; im Bereich **Spuren** kannst du ihr für Experimente eine eigene Tonleiter zuweisen.

## Akkordlabor

Wähle Grundton und Akkordtyp. Das Labor zeigt Symbol, Akkordtöne, Intervalle, harmonische Stufe und leiterfremde Töne. **Umkehrung ↑** und **Umkehrung ↓** verändern die Lage. Ziehe einen Notenkopf im Notenfeld vertikal, um das konkrete Voicing chromatisch zu verändern.

Der Bereich **In Szene übernehmen** steht direkt unter der Akkordauswahl. Wähle rechts oben einen Takt oder klicke eine Note in der Partitur; das Akkordlabor übernimmt diesen Takt automatisch. Mit **Takt** und **Zählzeit** kannst du die Position anschließend genau festlegen und den Akkord dort einsetzen – auch wenn davor noch keine Akkorde liegen. Bei einer bestehenden Folge kannst du außerdem am Ende anfügen, unmittelbar vor einem vorhandenen Akkord einfügen oder einen vorhandenen Akkord ersetzen. Nach der Aktion bestätigt Chordflow die resultierende Position. Beim Ersetzen bleiben Position und Dauer erhalten. Symbol und konkrete Tonhöhen werden gemeinsam gespeichert. Mit **Auf Tonleiter einrasten** landet ein gezogener Ton automatisch auf dem nächsten Ton der Szenentonleiter.

Ist der gewählte Zeitpunkt bereits belegt, zeigt das Akkordlabor den vorhandenen Akkord vor dem Einsetzen an. **Ersetzen** behält dessen Position und Dauer. **Davor** oder **Danach** fügt einen neuen Takt ein und verschiebt die nachfolgenden Akkorde. **Takt teilen** verteilt den vorhandenen und den neuen Akkord auf die Zählzeiten 1–2 und 3–4; die Reihenfolge kannst du vorher wählen. Bei längeren Akkordabschnitten bleiben die Teile vor und nach diesem Takt erhalten.

Das Akkordlabor spielt das aktuelle Voicing nach jeder Änderung kurz mit dem internen Pianoklang. Schalte **Nach Änderungen automatisch spielen** aus, wenn du still arbeiten möchtest. **Probehören** spielt den Akkord jederzeit manuell; dafür ist kein MIDI-Keyboard erforderlich.

Mit **←** und **→** gehst du im Akkordlabor genau einen Takt zurück oder vor. Solange derselbe Akkord gilt, bleibt er im Editor geladen und wird erneut zum Klangvergleich gespielt. Beim Erreichen eines neuen Akkords lädt Chordflow dessen Voicing. Mit **⌥←** und **⌥→** springst du unabhängig von seiner Dauer direkt zum vorherigen oder nächsten Akkord. Sobald du Grundton, Akkordtyp oder Voicing änderst, erscheint **Ungespeicherte Änderung**. Du kannst trotzdem weiter navigieren und mehrere Varianten im musikalischen Zusammenhang vergleichen. Chordflow hält jeden Entwurf getrennt fest: Die zugehörige Karte trägt das Badge **Entwurf**, und Akkordname sowie neue Noten erscheinen in der Partitur orange. Der zuletzt gespeicherte Akkord bleibt an derselben Position als hellgraue, zurückhaltende Geisterstimme sichtbar. **Änderung speichern** übernimmt nur den gerade geöffneten Entwurf; **Verwerfen** stellt dessen gespeicherten Akkord wieder her. **Als neuen Akkord verwenden** löst den geladenen Akkord als Vorlage von seiner Position, ohne vorhandene Entwürfe zu verlieren.

Die gleiche Navigation und Entwurfsverwaltung steht in der **Arrangement**-Ansicht zur Verfügung, sobald du eine Akkordkarte öffnest. Die zum aktiven Takt gehörende Karte wird automatisch sichtbar gescrollt und erhält einen phosphorgrünen Terminal-Glow; diese reine Fokusfarbe ist unabhängig von den musikalischen Rollenfarben. Der aktive Takt wird in der Partitur blau hervorgehoben, direkt am Notensystem mit seiner Taktnummer beschriftet und bei langen Partituren automatisch in die Mitte des sichtbaren Notenblatts bewegt.

Die Notationskarte verwendet denselben ABC-/abcjs-Renderer wie die vollständige Partitur. Schlüssel, Vorzeichen, Notenköpfe und Hilfslinien werden deshalb in beiden Ansichten identisch berechnet und gesetzt. Tiefe Voicings verwenden den Bassschlüssel, höhere den Violinschlüssel. Ziehe die Tonkarten unterhalb der Notation vertikal, um das Voicing mit der Maus zu verändern; die gemeinsame Partiturkomponente wird anschließend unmittelbar neu gerendert. Wiederholte Umkehrungen bleiben innerhalb des darstellbaren musikalischen Registers.

## Arrangement

Jede Karte ist ein Akkordereignis der Szene. Ziehe eine Karte auf eine andere, um die Reihenfolge zu verändern. Die Zahl der Zählzeiten bestimmt die Länge. Akkord- und Bassspur sowie die Partiturvorschau werden unmittelbar aus der Folge erzeugt; die Bassspur spielt dabei die jeweiligen Grundtöne.

## Quintenzirkel

Der äußere Name bezeichnet die Durtonart, der kleinere innere Name ihre parallele Molltonart. Ein Klick setzt das tonale Zentrum der Szene. Die App zeigt dazu Tonleiter, Dominante, Subdominante und Paralleltonart.

Nach einem Klick entscheidest du ausdrücklich zwischen **Nur Analyse ändern** und **Akkordfolge transponieren**. Die kontrollierte Transposition verschiebt gespeicherte Akkorde, Voicings und die daraus erzeugte Bassspur. Frei eingegebene Melodien bleiben unverändert.
