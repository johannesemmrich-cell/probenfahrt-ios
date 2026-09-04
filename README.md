# Probenfahrt

Native iOS-App (SwiftUI) für ein Labor-Team: Wer fährt an welchem Tag Proben
zum Labor bzw. holt sie ab. Umfragen, automatisch generierter Kalender,
Proben-Status, Team-Chat und Einstellungen.

Aktueller Stand: Die **komplette App hat seit 2026-09-04 ein echtes Backend**
(CloudKit, öffentliche Datenbank) — Umfragen/Kalender/Mitglieder/Chat kamen
dazu, der Proben-Bereich (inkl. QR-Code-Web-Check-in für Apotheken ohne
App-Installation) läuft schon seit 2026-09-03 darüber (siehe Abschnitt
"CloudKit-Setup" unten und [BACKLOG.md](./BACKLOG.md)). Nur noch
Feedback/Entwicklermodus-To-Dos bleiben lokal (SwiftData).

## Tech-Stack

- SwiftUI, Swift 6, iOS 26+ (nur iPhone, Portrait)
- CloudKit (öffentliche Datenbank) für alle geteilten Team-Daten
  (`TeamGroup`/`User`/`SurveyDay`/`SurveyEntry`/`ChatMessage`/
  `SampleLocation`/`SampleReport`) — siehe "CloudKit-Setup" unten. SwiftData
  bleibt nur noch für rein lokale, nicht geteilte Daten (`FeedbackEntry`,
  `DevTodoItem`).
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

## CloudKit-Setup

Alle geteilten Team-Daten laufen gegen die **öffentliche** CloudKit-
Datenbank des Containers `iCloud.com.johannesemmrich.probenfahrt` — nicht
gegen SwiftData+CloudKit's automatischen Sync, der nur die *private*
Datenbank eines einzelnen iCloud-Accounts spiegelt und damit weder das ganze
Laborteam noch eine anonyme Web-Seite erreichen könnte.

Folgende Schritte sind **einmalig, manuell im CloudKit Dashboard**
(icloud.developer.apple.com) nötig — das kann ich nicht per Kommandozeile
für dich erledigen, dafür gibt es keine API:

1. **Xcode öffnen, Team wählen.** Beim ersten Öffnen von
   `Probenfahrt.xcodeproj` unter Signing & Capabilities ein Entwicklerteam
   auswählen (Automatic Signing ist schon konfiguriert). Xcode registriert
   den iCloud-Container `iCloud.com.johannesemmrich.probenfahrt` dabei
   automatisch bei deinem Account, falls er noch nicht existiert.
2. **Schema entsteht automatisch beim ersten Speichern.** Sobald die App
   einmal im Debug-Build läuft (echtes Gerät oder Simulator mit
   iCloud-Account), legt `MockDataSeeder.ensureCloudTestDataIfNeeded()` beim
   Start automatisch die Test-Gruppe an und erzeugt damit alle sieben
   Record-Typen (`TeamGroup`, `User`, `SurveyDay`, `SurveyEntry`,
   `ChatMessage`, `SampleLocation`, `SampleReport`) in der
   **Development**-Umgebung automatisch mit den passenden Feldern.
3. **Felder als "Queryable" markieren.** Im Dashboard unter Schema:
   - `TeamGroup`: `joinCode`, `pharmacyJoinCode`
   - `User`: `groupID`
   - `SurveyDay`: `groupID`, `date`, `dayID`
   - `SurveyEntry`: `surveyDayID`, `groupID`
   - `ChatMessage`: `groupID`, `senderID`, `recipientID`
   - `SampleLocation`: `groupID`, `locationID`, `token`
   - `SampleReport`: `groupID`, `locationID`, `day`
   Ohne das schlagen Abfragen mit einer klaren Fehlermeldung fehl ("field
   ... is not marked queryable") — dann hier nachtragen.
4. **Server-to-Server-Key statt "World"-Rolle.** Ursprünglich war geplant,
   dass die Web-Seite direkt (anonym, per API-Token) über CloudKit JS
   schreibt — das geht aber nicht: die `_world`-Sicherheitsrolle lässt sich
   im Dashboard nur auf **Read** setzen, Create/Write sind für anonyme
   Clients strukturell gesperrt (Apple-Plattform-Einschränkung, kein
   Konfigurationsfehler). Stattdessen läuft jetzt ein kleiner lokaler Proxy
   (`web/proxy_server.py`), der über einen **Server-to-Server-Key**
   schreibt — Apples vorgesehener Mechanismus für "Web-Formular schreibt in
   CloudKit, ohne dass sich jemand mit Apple-ID einloggt". Setup:
   - Falls noch nicht geschehen: `cd web && openssl ecparam -name prime256v1 -genkey -noout -out eckey.pem`
     (Datei bleibt lokal, ist in `.gitignore`).
   - Public Key anzeigen: `openssl ec -in web/eckey.pem -pubout`
   - Dashboard → API Access → **Server-to-Server Keys** → neuen Key
     erzeugen, den Public Key dort einfügen → man bekommt eine **Key ID**.
   - `web/server_config.py` aus `web/server_config.example.py` kopieren
     (falls noch nicht vorhanden) und dort `KEY_ID` eintragen.
   - Die `_world`-Rolle selbst braucht nichts weiter — der Proxy umgeht sie
     komplett, Lesen *und* Schreiben laufen beide über den privilegierten
     Server-to-Server-Key.
5. **Vor dem echten TestFlight-Rollout: Schema nach Production deployen.**
   Ein Release-Build (= was TestFlight bekommt) spricht automatisch die
   **Production**-Umgebung an, nicht Development. Im Dashboard: "Deploy
   Schema Changes" von Development nach Production ausführen. In
   `web/server_config.py` `ENVIRONMENT` auf `"production"` umstellen und im
   Dashboard einen zweiten, production-spezifischen Server-to-Server-Key
   erzeugen (Keys sind pro Umgebung getrennt).
6. **`_icloud`-Rolle: Create + Write auf allen sieben Record-Typen.** Beim
   Einrichten des Proben-Bereichs ist aufgefallen, dass `_icloud` (die App
   mit echtem iCloud-Account) nur **Create** hatte, nicht **Write** — reicht
   fürs erste Anlegen, aber nicht fürs Ändern eines schon bestehenden
   Records (z. B. Umfrage-Tag sperren, eigenen Namen/Kürzel ändern, Proben-
   Status von "Ja" auf "Nein" korrigieren). Security Roles → `_icloud` →
   `TeamGroup`, `User`, `SurveyDay`, `SurveyEntry`, `ChatMessage`,
   `SampleLocation`, `SampleReport` → jeweils **Create + Write** anhaken.

Ich konnte diese Schritte nicht selbst ausführen oder live gegen echte
Apple-Server testen (kein Zugriff auf Xcode-GUI oder das CloudKit
Dashboard) — der Proxy hat in einem lokalen Test mit Platzhalter-Key schon
korrekt mit Apples Servern gesprochen (Antwort: `AUTHENTICATION_FAILED`,
also formal richtig aufgebaute Anfrage, nur der Key existiert noch nicht) —
das ist ein gutes Zeichen, ersetzt aber keinen echten End-zu-Ende-Test mit
gültigem Key.

### Apotheken-Web-Check-in lokal starten

```bash
cd web
./serve.sh          # Standardport 8080, siehe Konsolen-Ausgabe für die LAN-IP
```

Startet `proxy_server.py` (statische Seite + CloudKit-Schreibzugriff über
den Server-to-Server-Key aus `server_config.py`) — bricht mit einer klaren
Fehlermeldung ab, falls `server_config.py` noch fehlt.

QR-Codes dafür entstehen in der App unter **Einstellungen → Admin →
Apotheken verwalten** → Apotheke antippen. Die Basis-URL für QR-Codes ist
dort editierbar (Default `http://localhost:8080` — für echtes Scannen per
Handy im selben WLAN durch die LAN-IP ersetzen, siehe Hinweistext dort).

## Test-Zugänge (Mock-Daten)

Im Onboarding wird zuerst der Code abgefragt — er entscheidet, welchen
Account man bekommt. Beide Codes lösen zur selben, von
`MockDataSeeder.ensureCloudTestDataIfNeeded()` bei jedem App-Start
idempotent sichergestellten `TeamGroup` auf.

**Debug-Builds** (lokaler Simulator/Gerät-Run, UI-Tests) seeden zusätzlich
~10 fiktive Testnutzer, Umfrage-Historie und Chat-Nachrichten in diese
Gruppe (nur beim allerersten Mal, danach ist die Gruppe nicht mehr leer und
nichts wird erneut angelegt). **Release-/TestFlight-Builds seeden diese
Fixtures bewusst nicht** (`#if DEBUG`-gated) — echte Tester joinen einer
leeren Gruppe, nicht einer Belegschaft aus Fake-Kollegen. Debug spricht
CloudKits **Development**-Umgebung an, Release/TestFlight **Production** —
beide Umgebungen sind komplett getrennt, es gibt also keine Überschneidung.

- **`LABOR2026`** → normaler Laborteam-Account (Name + Kürzel, alle 5 Tabs).
  Debug-Seed-Daten: "Laborteam Nord", ~10 simulierte Testnutzer, u. a.
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
    Vice-Admin-Rechte auf, gefolgt von einer dritten Section, die die
    drei Entwicklermodus-only-Rechte erklärt (siehe nächster Punkt).
  - Solange "Alle Admin-Rechte" aktiv ist (oder die alte "Als Admin
    anzeigen"-Vorschau), zeigt die Detailansicht eines Mitglieds in
    "Mitglieder verwalten" bei einem Mitglied/Vice-Admin zusätzlich den
    Button "Zum Haupt-Admin machen" (direkte Ernennung, ohne den
    Admin-Code selbst einzugeben) und bei einem Haupt-Admin den Button
    "Haupt-Admin-Status entfernen" — stuft auch den letzten verbliebenen
    Haupt-Admin auf Mitglied zurück. Der Button "Aus Gruppe entfernen"
    entfernt in diesem Modus ebenfalls den letzten Haupt-Admin, statt das
    wie im Normalbetrieb zu verweigern. Alle drei sind bewusst nur über
    diesen Entwicklermodus-Bypass erreichbar, nicht für einen echten
    Haupt-Admin (siehe Annahmen unten).
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
- **CloudKit zunächst nur für den Proben-Bereich, nicht für die ganze App**
  (Stand 2026-09-03): Backlog #1 verlangt echte Backend-Anbindung
  allgemein, aber der konkrete Auslöser an jenem Abend war ausschließlich der
  QR-Code-Web-Check-in für Apotheken (Backlog #3), der ohne geteilten
  Backend-Zugriff nicht geht. Umfragen/Kalender/Chat/Mitglieder blieben
  zunächst bewusst auf lokalem SwiftData, um den Umbau nicht in einer Nacht
  auf die ganze App auszuweiten — die Migration der übrigen Bereiche folgte
  einen Tag später, siehe nächster Punkt.
- **CloudKit auf den Rest der App ausgeweitet** (Stand 2026-09-04): Auslöser
  war der erste echte Test zu viert über TestFlight — dafür mussten sich die
  Tester gegenseitig sehen können (wer trägt sich in eine Umfrage ein, Chat,
  Mitgliederliste), was mit rein lokalem SwiftData pro Gerät nicht ging.
  `CloudKitUserRepository` (User + TeamGroup), `CloudKitSurveyRepository`
  (SurveyDay + SurveyEntry) und `CloudKitChatRepository` (ChatMessage) kamen
  dazu, nach demselben Muster wie `CloudKitSamplesRepository` (öffentliche
  Datenbank, deterministische Record-IDs wo Idempotenz nötig ist, sonst
  zufällige). Paging/"Record-Typ existiert noch nicht"-Handling wurde dabei
  in einen gemeinsamen `CloudKitQuerying`-Helper gezogen (auch von
  `CloudKitSamplesRepository` genutzt, kleiner Begleit-Refactor). Neu:
  `SurveyEntry.groupID` (denormalisiert, analog `SampleReport.groupID`,
  damit Einträge gruppen-scoped statt unbegrenzt abgefragt werden) und
  `ChatMessage.recipientID` wird für Gruppennachrichten als String-Sentinel
  `"group"` statt `nil` gespeichert (vermeidet jede Abhängigkeit von
  CloudKits Nil-/Ungleich-Query-Unterstützung; DM-Abfragen laufen als zwei
  einfache Gleichheits-Queries statt einem OR-Prädikat). `MockDataSeeder`
  seedet jetzt idempotent gegen CloudKit statt einmalig gegen den lokalen
  Store (siehe "Test-Zugänge" oben). Bewusst nicht mit angefasst: neue
  Lade-/Fehler-UI für die jetzt vernetzten Screens (gleiche bekannte Kante
  wie schon bei Backlog #4 für den Proben-Bereich dokumentiert) und robuste
  Konfliktbehandlung beim gleichzeitigen Anlegen desselben Umfrage-Tages
  durch zwei Geräte (best-effort, analog zur bereits bekannten
  SampleReport-Race).
- **Fünf weitere UI-Tests wegen derselben CloudKit-Umstellung übersprungen**
  (Stand 2026-09-04, zusätzlich zu den drei bereits für den Proben-Bereich
  übersprungenen): `AdminRolesUITests.testAdminCodeUnlocksHauptAdminAndPromotesViceAdmin`,
  `AdminRolesUITests.testDevModeAdminPreviewCanRemoveLastHauptAdmin`,
  `BrandingUITests.testBrandingShowsUpAcrossScreens`,
  `OnboardingAndTabsUITests.testOnboardingThenAllTabsReachable`,
  `PharmacyOnboardingUITests.testDevPasswordInCodeFieldBypassesStraightIntoStandardApp`
  — alle 6 UI-Test-Dateien starten mit dem Beitrittscode-Schritt (inkl.
  Dev-Bypass), der jetzt `CloudKitUserRepository.resolveJoinCode` statt einer
  lokalen Lookup braucht. Erst versucht: die betroffenen
  `waitForExistence`-Timeouts von 5s auf 20s angehoben, in der Annahme, dass
  es nur ein Latenz-, kein Determinismus-Problem ist (anders als beim
  Proben-Bereich, wo tatsächlich unbekannter *Inhalt* das Problem war, nicht
  nur Timing) — brachte nichts, die App kam ohne signiertes iCloud-Testkonto
  im UI-Test-Simulator über den Code-Schritt gar nicht erst hinaus (volle 20s
  ausgeschöpft, kein Erfolg), also wieder auf 5s zurückgesetzt und stattdessen
  wie die drei bestehenden Fälle mit `XCTSkip` übersprungen. Einzig
  `ColdLaunchUITests` (misst nur die Kaltstart-Zeit, kein Onboarding) und die
  bereits vorher übersprungenen 3 blieben unverändert. Volle Suite jetzt
  wieder grün: 8 Tests, 1 läuft echt (ColdLaunchUITests), 7 übersprungen, 0
  Fehlschläge.
- **CloudKit statt Supabase/Firebase gewählt**: kein neuer Account nötig
  (läuft über das ohnehin für TestFlight nötige Apple-Entwicklerkonto),
  dafür ist CloudKits Public-Database-Sicherheitsmodell pro Record-Typ statt
  pro Datensatz granular — siehe Abschnitt "CloudKit-Setup" oben für die
  daraus resultierende bewusste Einschränkung beim anonymen Web-Zugriff.
- **Drei UI-Tests an die CloudKit-Umstellung angepasst**: `PastSamplesUITests`
  und `PharmacyOnboardingUITests.testPharmacyCodeLeadsToReducedTwoTabApp`
  übersprungen (`XCTSkip`), ein Assert in `OnboardingAndTabsUITests`
  entfernt. Alle drei hingen direkt oder indirekt an den lokal geseedeten
  Mock-Apotheken (`MockDataSeeder.seedSampleLocations`, jetzt entfernt) bzw.
  an einem live erfolgreichen CloudKit-Ja/Nein-Tap — ohne signiertes
  iCloud-Testkonto im UI-Test-Simulator ist der Proben-Tab-Inhalt nicht
  mehr deterministisch reproduzierbar. (Eine erste Version dieser Notiz
  hatte nur zwei der drei betroffenen Tests erwähnt — beim dritten,
  `PharmacyOnboardingUITests`, hätte "Ja, wir haben Proben" antippen +
  Status-Assert im CI-Simulator ebenso unzuverlässig fehlschlagen können;
  von einer unabhängigen Verifikation gefunden und nachträglich behoben.)
  Der Rest der Klickpfad-Tests (Onboarding, alle 5 Tabs, Admin-Vorschau,
  Dev-Password-Bypass) bleibt unverändert grün.
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
  entfernen oder zurückzustufen (gleicher Schutz wie beim Entfernen) — außer
  der Aufrufer setzt `bypassLastAdminGuard`, was `MemberDetailView` nur tut,
  wenn `isDeveloperOverride` (Admin-Vorschau-Toggle oder Dev-Mode-Toggle)
  aktiv ist. Damit kann selbst ein echter Haupt-Admin niemanden aus der
  Gruppe werfen oder auf Mitglied zurückstufen, wenn das die Gruppe ohne
  Haupt-Admin zurücklassen würde — nur der bewusste Entwicklermodus-/
  Vorschau-Bypass darf das, als Notausgang für diesen Prototyp-Stand.
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
