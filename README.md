# Probenfahrt

Native iOS-App (SwiftUI) für ein Labor-Team: Wer fährt an welchem Tag Proben
zum Labor bzw. holt sie ab. Umfragen, automatisch generierter Kalender,
Proben-Status, Team-Chat und Einstellungen.

Aktueller Stand: **Prototyp mit simulierten Mock-Daten** (lokal in
SwiftData), kein echtes Backend/keine echte Mehrbenutzer-Synchronisierung
(siehe [BACKLOG.md](./BACKLOG.md)).

## Tech-Stack

- SwiftUI, Swift 6, iOS 26+ (nur iPhone, Portrait)
- SwiftData für lokale Persistenz (kein CloudKit-Sync in diesem Schritt)
- Architektur: MVVM (`Models` / `Repositories` / `ViewModels` / `Views`)
- Repository-Pattern: Views/ViewModels sprechen nur mit Repository-
  Protokollen, nie direkt mit SwiftData — später kann eine echte Backend-
  Implementierung (Supabase/Firebase/CloudKit) dieselben Protokolle
  erfüllen, ohne dass UI-Code angefasst werden muss.
- Keine Third-Party-Dependencies (kein SPM-Paket nötig: PDF-Export läuft
  über `UIGraphicsPDFRenderer`, kein Router/State-Management-Package nötig)
- Swift Testing für die Kern-Businesslogik (Datums-/Wochenfenster-Berechnung,
  Monats-Auswertung), XCUITest für den kompletten Klickpfad (Onboarding →
  alle 5 Tabs)
- Projekt-Generierung über [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  `project.yml` ist die Quelle der Wahrheit, `Probenfahrt.xcodeproj` wird
  generiert und ist **nicht** eingecheckt (siehe `.gitignore`)

## Projekt öffnen

```bash
brew install xcodegen   # falls noch nicht installiert
xcodegen generate
open Probenfahrt.xcodeproj
```

## Build & Tests (Kommandozeile)

```bash
xcodegen generate
xcodebuild build -project Probenfahrt.xcodeproj -scheme Probenfahrt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -project Probenfahrt.xcodeproj -scheme Probenfahrt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Kein Apple-Entwicklerkonto/Team nötig für Simulator-Builds (kein CloudKit,
keine Push-Capabilities in diesem Schritt) — `CODE_SIGN_STYLE: Automatic`
in `project.yml` reicht aus.

**Falls der Simulator beim Start hängt (weißer Screen, dreht sich endlos):**
Das lag bei uns am iOS-26.5-Runtime-Image, nicht an der App — mit iPhone 17
Pro auf **iOS 26.4.1** lief der Start zuverlässig. Falls das nochmal
auftritt: in Xcode oben rechts einfach auf ein Gerät mit einer anderen
iOS-Runtime-Version wechseln (Window → Devices and Simulators zeigt
installierte Runtimes). Kein Debugging-/Entwicklerkonto-Problem — separat
geprüft (auch mit deaktiviertem "Debug executable" trat es weiter auf).

## Test-Zugänge (Mock-Daten)

- **Gruppen-Beitrittscode:** `LABOR2026` ("Laborteam Nord", ~10 simulierte
  Testnutzer, u.a. "Johannes Emmrich" als Admin)
- **Proben-Tab-Freischaltcode:** `PROBEN2026` (einfacher simulierter Check,
  siehe Backlog #1)
- **Admin-Vorschau:** In den Einstellungen gibt es einen klar markierten
  Dev-Toggle "Als Admin anzeigen" — jeder frisch onboardete Testnutzer ist
  regulär "member", kann sich damit aber die Admin-Ansichten anschauen.

## Annahmen

Wird laufend ergänzt, sobald offene Detailfragen aus der Spezifikation mit
einer sinnvollen Annahme beantwortet werden.

- **Ursprünglich als PWA begonnen, dann auf native App umgestellt**: Die
  Spezifikation beschrieb zunächst eine PWA (Vite+React+Tailwind), auf
  Rückfrage wurde klar, dass eine native SwiftUI/Xcode-App gewünscht ist
  (wie die anderen Apps). Der PWA-Ansatz wurde verworfen; ein Reste-Scaffold
  liegt noch unter `~/Developer/Probenfahrt` (kann bei Bedarf gelöscht
  werden).
- **Projektname/-ort**: Arbeitstitel "Probenfahrt", Ordner
  `~/Developer/Probenfahrt-iOS` (Namenskonflikt mit dem alten PWA-Ordner
  vermeiden). Reines Umbenennen ist jederzeit möglich.
- **Bundle-ID / Konventionen**: an Sunwake/GymTrack angelehnt
  (`com.johannesemmrich.probenfahrt`, XcodeGen, iOS 26 Deployment-Target,
  Swift 6, nur iPhone/Portrait, `.xcodeproj` nicht eingecheckt).
- **Kein CloudKit in diesem Schritt**: Die Spezifikation verlangt explizit
  nur simulierte Mock-Daten, kein echtes Backend. Lokale SwiftData-
  Persistenz ohne Sync erfüllt das; CloudKit- oder Supabase/Firebase-Sync
  ist Backlog #3.
- **Onboarding-Reihenfolge**: Name/Kürzel wird zuerst erfasst, aber erst
  geprüft, sobald der Gruppencode die Gruppe auflöst (Kürzel-Eindeutigkeit
  ist von Anfang an pro Gruppe geprüft, nicht global — auch wenn aktuell
  nur eine Gruppe existiert). Bei Konflikt geht es mit Fehlermeldung zurück
  zum Namens-Schritt, ohne dass Name/Kürzel neu eingegeben werden müssen.
- **Proben-Tab-Freischaltung bleibt pro Gerät bestehen**: Einmal korrekt
  eingegeben, muss der Code nicht bei jedem Tab-Wechsel neu eingegeben
  werden (lokal in UserDefaults gemerkt).
- **Rollierendes Umfragen-Fenster**: Umfrage-Tage für die nächsten 2 Wochen
  werden bei Bedarf automatisch angelegt (nicht fest vorab erzeugt), damit
  das Fenster auch nach Wochen App-Nutzung ohne Hintergrund-Job korrekt
  weiterrollt. Kalender/vergangene Umfragen lesen nur bestehende Tage,
  ohne welche anzulegen.
- **Kalender-Optik**: volle 7-Tage-Woche (klassischer App-Kalender-Look),
  Fr/Sa/So bleiben aber immer leer/inaktiv, da die Spezifikation nur Mo–Do
  vorsieht.
- **UI-Sprache immer Deutsch**: Datumsformatierung erzwingt `de_DE`
  unabhängig von der Geräte-/Simulator-Spracheinstellung.
- **Verifikation**: Build, Unit-Tests (Swift Testing) und ein XCUITest, der
  den kompletten Klickpfad (Onboarding, alle 5 Tabs, Proben-Freischaltung,
  Admin-Vorschau-Toggle) durchspielt, laufen grün. Zusätzlich per Screenshot
  aus den Testläufen visuell geprüft (u. a. dabei zwei echte Bugs gefunden
  und behoben: fehlende Locale-Erzwingung bei Datumsanzeigen und ein
  Scroll-Glitch im Chat bei kurzen Konversationen).
