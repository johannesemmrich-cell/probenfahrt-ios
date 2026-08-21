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
- Swift Testing für die Kern-Businesslogik (Datums-/Wochenfenster-Berechnung
  inkl. Freitags-Rollover, Editier-Rechte, Monats-/Mitglieder-Auswertung),
  XCUITest für den kompletten Klickpfad (Onboarding → alle 5 Tabs)
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

Im Onboarding wird zuerst der Code abgefragt — er entscheidet, welchen
Account man bekommt:

- **`LABOR2026`** → normaler Laborteam-Account (Name + Kürzel, alle 5 Tabs).
  Seed-Daten: "Laborteam Nord", ~10 simulierte Testnutzer, u. a.
  "Johannes Emmrich" als Admin.
- **`PROBEN2026`** → Apotheken-/Zulieferer-Account: Statt Name/Kürzel wird
  nur ein Apotheken-/Firmenname abgefragt. Dieser Account bekommt nur 2 Tabs
  (Proben, Einstellungen); im Proben-Tab gibt's ausschließlich die Auswahl
  "Ja, wir haben Proben" / "Keine Proben" für heute — das Ergebnis erscheint
  dann im normalen Proben-Tab des Laborteams.
- **Entwicklermodus-Bypass im Onboarding:** Statt eines Beitrittscodes das
  Dev-Mode-Passwort (`Isg#45krusgL.`) eingeben → man landet direkt im
  Standard-Laborteam-Account (wiederverwendbarer Testnutzer "Entwickler",
  Kürzel `DEV`) mit bereits aktivem Entwicklermodus. Funktioniert nur,
  solange es die zwei Demo-Codes oben gibt.
- **Haupt-Admin-Code:** Ganz unten in den Einstellungen (nur Laborteam-
  Accounts, die noch nicht Haupt-Admin sind) gibt es ein Code-Feld — Code
  `Admin` eingeben schaltet den eigenen Account dauerhaft auf Haupt-Admin
  frei (echte, persistierte Rollenänderung, kein Preview-Toggle). Bewusst
  einfach/im Klartext für diesen Prototyp-Stand.
- **Admin-Vorschau:** In den Einstellungen (nur Laborteam-Accounts) gibt es
  einen klar markierten Dev-Toggle "Als Admin anzeigen" — jeder frisch
  onboardete Testnutzer ist regulär "member", kann sich damit aber die
  Admin-Ansichten anschauen. Im Entwicklermodus (siehe unten) gibt es
  zusätzlich einen gleichwertigen Toggle "Alle Admin-Rechte", der diesen
  Preview-Toggle ersetzen soll, sobald er selbst entfernt wird.
- **Entwicklermodus (Feedback/To-Do):** 5x auf die Versionsnummer unten in
  den Einstellungen tippen, Passwort `Isg#45krusgL.` eingeben. Zeigt danach
  ein 👎-Feedback-Overlay auf allen Tabs und einen Feedback-/To-Do-
  Bereich in den Einstellungen (analog zu Sunwakes Entwicklermodus). Bei
  aktivem Entwicklermodus gibt's zusätzlich in "Entwicklung":
  - Toggle "Proben-Tab (Apotheke) als Extra-Tab" — blendet die
    Apotheken-Proben-Ansicht als 6. Tab ein, ohne den Account-Typ zu wechseln.
  - Button "Zu Apotheken-Modus wechseln" — schaltet die komplette App
    (Tabs + Einstellungen) probeweise auf die 2-Tab-Apotheken-Ansicht um;
    ein gleichwertiger Button schaltet von dort wieder zurück.
  - Beide Vorschauen legen dafür einen eigenen `SampleLocation`-Testeintrag
    unter dem eigenen Namen an; sobald beide Vorschau-Schalter wieder aus
    sind, wird dieser Testeintrag automatisch gelöscht (sonst bliebe er
    dauerhaft und für das ganze Team sichtbar im echten Proben-Tab stehen).
  - Toggle "Alle Admin-Rechte (Haupt-Admin)" — wie "Als Admin anzeigen" in
    den Einstellungen, nur innerhalb des Entwicklermodus statt daneben.
  - Zwei Übersichts-Sections listen alle Haupt-Admin- und alle
    Vice-Admin-Rechte auf.
- **Über/Datenschutz + Emmrich-Banner:** In den Einstellungen gibt es einen
  "Über"-Bereich (Über Probenfahrt, Datenschutz) sowie ganz unten das
  "Mehr von Emmrich"-Banner (verlinkt auf emmrich-business.com) — analog
  zu Sunwakes Einstellungen, mit den fixen Emmrich-Markenfarben.

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
- **Onboarding-Reihenfolge**: Der Code wird zuerst erfasst, weil er
  entscheidet, welcher Identitäts-Schritt danach kommt (Name+Kürzel fürs
  Laborteam vs. nur Firmenname für Apotheken) — Kürzel-Eindeutigkeit wird
  weiterhin pro Gruppe geprüft (nicht global, auch wenn aktuell nur eine
  Gruppe existiert). Bei Konflikt geht es mit Fehlermeldung zurück zum
  Code-Schritt.
- **Zwei Account-Typen über zwei Join-Codes**: `AccountKind` (labTeam/
  pharmacy) hängt am `User`, nicht an der Gruppe — beide Codes lösen zur
  selben `TeamGroup` auf, nur der jeweils passende Code
  (`joinCode`/`pharmacyJoinCode`) bestimmt den Account-Typ. So bleibt es
  eine einzige Mock-Gruppe, ohne dass Apotheken und Laborteam getrennte
  Datensilos bräuchten.
- **Proben-Tab jetzt mit echter Interaktionslogik**: Apotheken-Accounts
  haben eine eigene, an sie gebundene `SampleLocation`
  (`ownerUserID`), die sie selbst per Ja/Nein-Auswahl für den aktuellen Tag
  pflegen — damit ist die in Backlog früher offene "echte
  Interaktionslogik" gelöst. Die alten, nicht an einen Account gebundenen
  Mock-Standorte bleiben als zusätzliche Demo-Einträge bestehen.
- **Umfragen als zwei Kalenderwochen-Blöcke mit Freitags-Rollover**:
  "Fahrplan"-Block 1 = die "aktuelle" Kalenderwoche (Mo–Do), Block 2 = die
  Woche danach — nicht mehr ein rollierendes 14-Tage-Fenster ab heute. Da
  Mo–Do die einzigen Umfrage-Tage sind, gilt eine Woche ab Freitag als
  durch: an Fr/Sa/So zeigen die 2 aktuellen Blöcke bereits die nächste
  Woche + die Woche danach, und die gerade abgelaufene Woche rutscht in
  "Vergangene Umfragen" (für alle sichtbar, aber nur Admin kann dort noch
  etwas ändern — sobald das Datum eines Umfrage-Tags in der Vergangenheit
  liegt, gilt das auch innerhalb der 2 aktuellen Blöcke, z. B. für Mo/Di
  einer noch laufenden Woche, wenn heute Mittwoch ist). "Vergangene
  Umfragen" gruppiert ebenfalls in "Fahrplan vom...bis..."-Wochenblöcke
  (bis zu 8 Wochen zurück, neueste zuerst) statt einer flachen Liste —
  gleiche Optik wie die 2 aktuellen Blöcke, nur ohne "Aktuell"-Badge.
  Umfrage-Tage werden weiterhin bei Bedarf automatisch angelegt, nicht
  fest vorab erzeugt.
  Kalender/vergangene Umfragen lesen nur bestehende Tage, ohne welche
  anzulegen.
- **Dreistufiges Rollensystem: Haupt-Admin, Vice-Admin, Mitglied**:
  `UserRole` hat jetzt `.admin` (Haupt-Admin), `.viceAdmin` und `.member`.
  `isEffectiveAdmin` ist true für beide Admin-Stufen (steuert z. B.
  Umfragen-Verwaltung, PDF-Export, Sichtbarkeit von "Mitglieder verwalten");
  `isFullAdmin` nur für Haupt-Admin (steuert exakt 3 Dinge: Mitglieder
  entfernen, Kürzel ändern, Vice-Admin ernennen/zurückstufen — über einen
  Regler in "Mitglieder verwalten"). Beide Preview-Overrides ("Als Admin
  anzeigen" und der neue Dev-Mode-Toggle) zählen für `isFullAdmin`, nicht
  nur für `isEffectiveAdmin` — sie sollen weiterhin volle Admin-Vorschau
  bleiben, nicht nur Vice-Admin-Vorschau. `UserRepository.setRole`/
  `deleteUser` weigern sich, den letzten Haupt-Admin einer Gruppe zu
  entfernen oder zurückzustufen (gleicher Schutz wie beim Entfernen).
- **Admin verwaltet vergangene Tage über "Verwalten" statt Eintragen-Knopf**:
  Sobald ein Umfrage-Tag in der Vergangenheit liegt, verschwindet der
  einfache Eintragen/Austragen-Knopf auch für Admins — stattdessen führt ein
  "Verwalten"-Link in die Tagesansicht, in der Admins jede Person einzeln
  ein-/austragen können (nicht nur sich selbst). Auf zukünftigen/heutigen
  Tagen bleibt der normale Selbst-Eintragen-Knopf für alle unverändert.
- **Kürzel nach dem Setzen fix**: Nur beim Onboarding frei wählbar; danach
  kann ein normaler Nutzer sein eigenes Kürzel nicht mehr ändern — nur ein
  Admin kann es über "Einstellungen → Admin → Mitglieder verwalten"
  korrigieren. Dort sieht der Admin pro Person auch Beitrittsdatum,
  Fahrten insgesamt sowie Fahrten pro Woche/Monat (mit Vor-/Zurück-
  Navigation), und kann Personen aus der Gruppe entfernen — außer sich
  selbst (verhindert einen versehentlichen Selbst-Lockout, da die Session
  sonst auf einen gelöschten Nutzer zeigen würde) und außer dem letzten
  verbleibenden Admin der Gruppe (sonst gäbe es niemanden mehr, der
  Admin-Rechte vergeben könnte). Vergangene Fahrten bleiben beim Entfernen
  erhalten (lose UUID-Referenz, kein Cascade-Delete — passt zum
  bestehenden Muster bei SurveyEntry).
- **Kalender-Optik**: volle 7-Tage-Woche (klassischer App-Kalender-Look),
  Fr/Sa/So bleiben aber immer leer/inaktiv, da die Spezifikation nur Mo–Do
  vorsieht.
- **UI-Sprache immer Deutsch**: Datumsformatierung erzwingt `de_DE`
  unabhängig von der Geräte-/Simulator-Spracheinstellung.
- **Verifikation**: Build, Unit-Tests (Swift Testing) und ein XCUITest, der
  den kompletten Klickpfad (Onboarding, alle 5 Tabs, Admin-Vorschau-Toggle,
  Über/Datenschutz/Emmrich-Banner, Vergangene Umfragen) durchspielt, laufen grün. Zusätzlich per
  Screenshot aus den Testläufen visuell geprüft (u. a. dabei zwei echte Bugs
  gefunden und behoben: fehlende Locale-Erzwingung bei Datumsanzeigen und
  ein Scroll-Glitch im Chat bei kurzen Konversationen). Der neue Apotheken-
  Onboarding-Flow und die Mitglieder-Verwaltung sind aktuell nur durch
  Unit-Tests der zugrundeliegenden Logik abgedeckt, nicht per XCUITest.
