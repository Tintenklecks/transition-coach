# Transition Coach

Transition Coach begleitet Menschen durch zeitkritische Routinen. Im Mittelpunkt steht nicht die Uhr, sondern die konkrete Frage: **Was sollte ich genau jetzt tun?**

## Aktueller Stand

Der erste nutzbare iPhone-/iPad-/Mac-Prototyp enthält:

- eine rückwärts aus der Zielzeit berechnete Morgenroutine
- eine große, farbcodierte „Jetzt“-Ansicht
- Countdown und Tagesfortschritt
- tägliche lokale Hinweise für jeden Übergang
- einen Editor für Zielzeit, Puffer, Reihenfolge und Dauer der Schritte
- eine persistente Beispielroutine für den direkten Einstieg

Die Farbsemantik ist fest: Blau bereitet vor, Gelb markiert den Wechsel, Orange zeigt Verzögerung, Rot eine gefährdete Zielzeit und Grün den Abschluss.

## Architektur

Routinen und Schritte werden mit SwiftData gespeichert. Die Zeitplanung liegt getrennt davon in einem reinen `ScheduleCalculator`, damit dieselbe Logik später von iPhone, Apple Watch, Widgets und macOS verwendet und unabhängig getestet werden kann. Benachrichtigungen werden lokal je Gerät geplant; eine spätere CloudKit-Synchronisation muss deshalb nur die Routinedaten übertragen.

## Nächste sinnvolle Ausbaustufen

1. Apple-Watch-Oberfläche und WatchConnectivity
2. CloudKit-Synchronisation
3. Eskalationen und interaktive Notification-Aktionen
4. Wochenziele und ausschließlich positive Gamification
5. App-Store-Texte, Onboarding, Datenschutz und Barrierefreiheitsprüfung

Die ausführliche Produktvision steht in [ProjectIdea.md](ProjectIdea.md).
