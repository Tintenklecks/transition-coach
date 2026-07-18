# ProjectIdea.md

# Transition Coach

## Vision

Menschen haben oft kein Problem damit, die Uhr zu lesen.

Sie haben ein Problem damit, den richtigen Zeitpunkt zum Wechseln einer Tätigkeit zu erkennen.

Die eigentliche Herausforderung ist nicht die Uhrzeit, sondern der Übergang.

Diese App soll genau diese Übergänge unterstützen.

Sie soll den Benutzer nicht einfach erinnern, sondern Schritt für Schritt durch eine zeitkritische Routine begleiten.

---

# Motivation

Ausgangspunkt ist die Beobachtung, dass manche Menschen trotz bekannter Termine regelmäßig zu spät losgehen.

Beispiel:

- Arbeitsbeginn: 08:45 Uhr
- Um 08:40 Uhr wird noch konzentriert am Computer gearbeitet.
- Der notwendige Zeitbedarf für Bad, Anziehen und Arbeitsweg wird in diesem Moment nicht mehr richtig wahrgenommen.

Das Ziel ist daher nicht, eine weitere Erinnerungs-App zu entwickeln.

Das Ziel ist, den Wechsel zwischen Tätigkeiten aktiv zu begleiten.

---

# Problem Statement

Klassische Wecker und Notifications erinnern lediglich an eine Uhrzeit.

Sie helfen jedoch kaum dabei,

- eine Tätigkeit bewusst zu beenden,
- den nächsten Schritt einzuleiten,
- die verbleibende Zeit richtig einzuschätzen.

Dadurch entsteht häufig Stress, Hektik und Verspätung.

---

# Produktidee

Die App versteht eine Morgenroutine als eine Folge von Zuständen.

Nicht:

> "Es ist 08:15."

Sondern:

> "Jetzt ist der richtige Zeitpunkt, den Computer zu verlassen."

Jeder Schritt besitzt:

- eine Dauer
- einen geplanten Startzeitpunkt
- Warnungen
- Eskalationen
- optional eine Bestätigung

Die Routine wird rückwärts aus einer Zielzeit berechnet.

Beispiel:

Arbeitsbeginn

↓

Späteste Abfahrt

↓

Schuhe

↓

Tasche

↓

Anziehen

↓

Bad

↓

Computer verlassen

---

# Leitprinzip

Nicht die Uhrzeit ist wichtig.

Der aktuelle Schritt ist wichtig.

Die App soll jederzeit beantworten:

> "Was sollte ich genau jetzt tun?"

---

# Plattformen

Geplant sind:

- iPhone
- Apple Watch
- iPad
- macOS

Jedes Gerät übernimmt eine sinnvolle Rolle.

### Apple Watch

- Haptische Hinweise
- Countdown
- Bestätigung
- +2 Minuten

### iPhone

- Haupt-App
- Routinen bearbeiten
- Notifications
- Alarme

### macOS

Besonders wichtig während konzentrierter Computerarbeit.

Mögliche Funktionen:

- Menüleisten-Countdown
- Vollbild-Overlay
- deutliche Übergangshinweise

---

# Synchronisation

Die Geräte sollen dieselben Routinen verwenden.

CloudKit und SwiftData reichen zunächst vollständig aus.

Jedes Gerät plant seine eigenen lokalen Erinnerungen.

Die Synchronisation dient ausschließlich den Daten.

Nicht der Echtzeitsteuerung.

---

# Notifications

Nicht alle Hinweise sind gleich wichtig.

Geplant sind mehrere Ebenen.

## Vorwarnung

"Der nächste Schritt beginnt gleich."

Ruhige Notification.

---

## Übergang

"Jetzt Computer verlassen."

Deutlich sichtbarer Hinweis.

Watch-Haptik.

---

## Eskalation

Keine Reaktion.

Kräftiger Alarm.

Deutlichere Darstellung.

---

# Farben

Farben besitzen eine feste Bedeutung.

Blau

→ Vorbereitung

Gelb

→ Jetzt wechseln

Orange

→ Noch keine Reaktion

Rot

→ Termin gefährdet

Nicht frei konfigurierbar.

Die Semantik soll immer gleich bleiben.

---

# Gamification

Gamification dient ausschließlich dazu, gewünschtes Verhalten positiv zu verstärken.

Nicht zur Bestrafung.

## Punkte

Positive Punkte für:

- Schritt rechtzeitig begonnen
- Schritt abgeschlossen
- Puffer gewonnen
- gesamte Routine geschafft
- rechtzeitig losgegangen

Keine Minuspunkte.

---

## Streaks

Keine harten Streaks.

Lieber Wochenziele.

Zum Beispiel:

4 von 5 Routinen geschafft.

Dadurch wird verhindert, dass ein schlechter Morgen eine komplette Serie zerstört.

---

## Badges

Badges markieren Fortschritte.

Beispiele:

- Erste komplette Routine
- Drei stressfreie Morgen
- Ohne Eskalation
- Puffer-Profi
- Zurück im Rhythmus

Der Badge

"Zurück im Rhythmus"

ist besonders wichtig.

Er belohnt das Wiederanfangen.

Nicht Perfektion.

---

# Erfolgsmessung

Nicht entscheidend ist,

wie oft ein Button gedrückt wurde.

Entscheidend ist,

ob die Person entspannter und pünktlicher das Haus verlässt.

Mögliche Kennzahlen:

- durchschnittlicher Puffer
- durchschnittliche Abfahrtszeit
- Eskalationsrate
- schwierige Übergänge
- erfolgreiche Übergänge

---

# Designprinzipien

Die App soll niemals Schuldgefühle erzeugen.

Ein schlechter Morgen ist kein Versagen.

Er liefert lediglich Informationen.

Die App unterstützt.

Sie bewertet nicht.

---

# Langfristige Vision

Die App soll Menschen helfen,

Zeitübergänge bewusster wahrzunehmen,

Stress vor Terminen zu reduzieren,

Routine aufzubauen

und Schritt für Schritt bessere Gewohnheiten zu entwickeln.

---

# Leitsatz

> Eine App, die Zeitübergänge strukturiert, rechtzeitiges Handeln unmittelbar belohnt und Fortschritt sichtbar macht, ohne schlechte Tage zu bestrafen.
