---
title: Akkorde und Musiktheorie
summary: Akkorde entwerfen, Tonleitern untersuchen und Folgen für eine Szene planen.
order: 25
keywords: [Akkord, Tonleiter, Quintenzirkel, Voicing, Arrangement]
---

Jede Szene besitzt einen Grundton und eine Tonleiter. Wähle beides oberhalb des Arbeitsbereichs. Eine Spur verwendet standardmäßig **Wie Szene**; im Bereich **Spuren** kannst du ihr für Experimente eine eigene Tonleiter zuweisen.

## Einfach und Erweitert

Mit **Einfach | Erweitert** wechselst du zwischen zwei Bedienebenen. **Einfach** konzentriert sich auf große Akkordkarten, Anhören, Hinzufügen und verständliche Klangbegriffe. Grundton heißt dort **Startton**, Akkordtyp heißt **Klangart**, und die harmonischen Funktionen werden zusätzlich als **Zuhause**, **Reise** und **Spannung** erklärt. Die Partitur bietet **Ein Takt | Ganze Partitur** und blendet MIDI-Export, Mehrfachauswahl und technische Farblegenden zunächst aus.

**Warum klingt das so?** öffnet die Musiktheorie direkt im Inspector. **Mehr über diesen Klang entdecken** führt zur großen Ansicht mit Notation, Klaviatur und Voicing-Bearbeitung. **Erweitert** zeigt alle Fachbegriffe, Analysevarianten und Partiturwerkzeuge dauerhaft. Dadurch kann man einfach beginnen und die korrekten musikalischen Begriffe schrittweise kennenlernen.

## Akkordfolge, Inspector und Detailmodus

Die bisher getrennten Bereiche **Arrangement** und **Akkordlabor** sind in **Akkordfolge** zusammengeführt. Beim Öffnen wird der erste Akkord ohne automatische Tonwiedergabe ausgewählt, sodass Karte, Inspector und Partitur sofort einen gemeinsamen Fokus besitzen. Ein Klick auf eine andere Karte markiert den Akkord grün, zentriert seinen Takt in der Partitur und lädt ihn rechts in den Inspector. Dort änderst du Grundton, Akkordtyp und Lage, hörst das Voicing ab und speicherst oder verwirfst den Entwurf, ohne den Zusammenhang der Folge zu verlassen.

Unter jeder Karte fügt **Akkord danach** direkt an dieser Stelle einen neuen Akkord ein und wählt ihn sofort zur Bearbeitung aus. Eine leere Folge bietet entsprechend **Ersten Akkord anlegen** an. Karten lassen sich weiterhin ziehen, um ihre Reihenfolge zu verändern.

Der Inspector erklärt Typ, Töne, Intervalle, harmonische Stufe und die Rolle jedes einzelnen Akkordtons. Unter **Im harmonischen Zusammenhang** vergleicht er den Akkord zusätzlich mit seinen beiden Nachbarn und nennt gemeinsame Liegetöne sowie Halbtonbewegungen. Damit kannst du Harmonie und Stimmführung während der Bearbeitung gemeinsam beurteilen.

**Detailmodus** öffnet die große Arbeitsfläche mit gesetzter Notation, einzeln verschiebbaren Voicing-Tönen, ausführlicher Tonanalyse und einklappbarer Klaviatur. **Lage höher** setzt den tiefsten Akkordton eine Oktave nach oben, **Lage tiefer** entsprechend den höchsten Ton nach unten. **Probehören** spielt das aktuelle Voicing mit dem internen Pianoklang; dafür ist kein MIDI-Keyboard erforderlich.

Mit **←** und **→** gehst du in Akkordfolge und Detailmodus genau einen Takt zurück oder vor. Solange derselbe Akkord gilt, bleibt er im Editor geladen und wird erneut zum Klangvergleich gespielt. Beim Erreichen eines neuen Akkords lädt Chordflow dessen Voicing. Mit **⌥←** und **⌥→** springst du unabhängig von seiner Dauer direkt zum vorherigen oder nächsten Akkord. Sobald du Grundton, Akkordtyp oder Voicing änderst, erscheint **Ungespeicherte Änderung**. Du kannst trotzdem weiter navigieren und mehrere Varianten im musikalischen Zusammenhang vergleichen. Chordflow hält jeden Entwurf getrennt fest: Die zugehörige Karte trägt das Badge **Entwurf**, und Akkordname sowie neue Noten erscheinen in der Partitur pink. Der zuletzt gespeicherte Akkord bleibt an derselben Position als hellgraue, zurückhaltende Geisterstimme sichtbar. **Speichern** übernimmt nur den gerade geöffneten Entwurf; **Verwerfen** stellt dessen gespeicherten Akkord wieder her.

Die zum aktiven Takt gehörende Karte wird automatisch sichtbar gescrollt und erhält einen phosphorgrünen Terminal-Glow. Aktive beziehungsweise gerade gespielte Noten verwenden denselben grünen Glow in der Partitur. Diese reine Fokusfarbe ist unabhängig von den musikalischen Strukturfarben: Grundstellung ist blau, Umkehrung lila und veränderte Struktur beziehungsweise Entwurf pink. Der aktive Takt wird direkt am Notensystem mit seiner Taktnummer beschriftet und bei langen Partituren automatisch in die Mitte des sichtbaren Notenblatts bewegt.

Kartenraster und Partitur verwenden dieselbe vertikale Fokuslinie in der Bildschirmmitte. Beim Auswählen oder Navigieren werden aktive Akkordkarte und aktiver Takt deshalb synchron auf dieselbe Höhe geführt. Zusätzlicher Scrollraum ober- und unterhalb der Inhalte ermöglicht diese Zentrierung auch beim ersten und letzten Akkord.

Über der Partitur schaltet **Fokus** auf eine ruhige, gleichbleibend hohe Arbeitsansicht, in der der aktive Takt automatisch zentriert wird. Während das Akkordfenster geöffnet ist, wird die umgebende Partitur in diesem Modus sanft unscharf. **Ganze Partitur** klappt den großen Editor zu einer kleinen schwebenden Leiste zusammen, zeigt das vollständige Notenblatt scharf und rastet nach dem Layoutwechsel erneut auf dem aktiven Takt ein. Der Takt und seine Noten sowie die zugehörige Arrangement-Karte tragen dabei weiterhin den grünen Fokus-Glow. Auch in dieser Ansicht navigierst du mit **←/→** taktweise und mit **⌥←/⌥→** akkordweise; die Leiste enthält dieselben Navigationsschalter. Über die Leiste wechselst du zurück zu **Fokus** oder schließt die Akkordbearbeitung. Im Akkordfenster sind die harmonische Einordnung und die Klaviatur einklappbar, damit beim Vergleichen vor allem Akkord, Notation und Voicing sichtbar bleiben.

Die Notationskarte verwendet denselben ABC-/abcjs-Renderer wie die vollständige Partitur. Schlüssel, Vorzeichen, Notenköpfe und Hilfslinien werden deshalb in beiden Ansichten identisch berechnet und gesetzt. Tiefe Voicings verwenden den Bassschlüssel, höhere den Violinschlüssel. Ziehe die Tonkarten unterhalb der Notation vertikal, um das Voicing mit der Maus zu verändern; die gemeinsame Partiturkomponente wird anschließend unmittelbar neu gerendert. Wiederholte Umkehrungen bleiben innerhalb des darstellbaren musikalischen Registers.

## Akkordkarten

Jede Karte ist ein Akkordereignis der Szene. Ziehe eine Karte auf eine andere, um die Reihenfolge zu verändern. Die Zahl der Zählzeiten bestimmt die Länge. Akkord- und Bassspur sowie die Partiturvorschau werden unmittelbar aus der Folge erzeugt; die Bassspur spielt dabei die jeweiligen Grundtöne.

## Quintenzirkel

Der äußere Name bezeichnet die Durtonart, der kleinere innere Name ihre parallele Molltonart. Ein Klick setzt das tonale Zentrum der Szene. Die App zeigt dazu Tonleiter, Dominante, Subdominante und Paralleltonart.

Nach einem Klick entscheidest du ausdrücklich zwischen **Nur Analyse ändern** und **Akkordfolge transponieren**. Die kontrollierte Transposition verschiebt gespeicherte Akkorde, Voicings und die daraus erzeugte Bassspur. Frei eingegebene Melodien bleiben unverändert.
