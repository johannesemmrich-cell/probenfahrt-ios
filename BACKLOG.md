# Backlog

Neue Einträge werden hier NUR ergänzt, wenn im Chat explizit "Backlog:" oder
"ins Backlog" gesagt wird. Andere Ideen/offene Punkte, die während der
Entwicklung auffallen, werden im Chat angesprochen statt automatisch hier
ergänzt.

1. Echte Backend-/Datenbank-Anbindung (z.B. Supabase/Firebase oder CloudKit-
   Sync) für echte Mehrbenutzer-Synchronisierung, als Ersatz für die lokale
   SwiftData-Mock-Schicht. **Teilerledigt (2026-09-03):** Proben-Bereich
   (`SampleLocation`/`SampleReport`) läuft jetzt über CloudKit (öffentliche
   Datenbank), siehe README.md "CloudKit-Setup". Umfragen/Kalender/Chat/
   Mitglieder bleiben bewusst noch auf lokalem SwiftData.
2. Echte Rollen-/Rechteprüfung (Haupt-Admin vs. Vice-Admin vs. normaler
   Nutzer, Apotheke vs. Laborteam) technisch durchsetzen (Auth statt
   Dev-Toggle "Als Admin anzeigen"/Dev-Mode-Admin-Vorschau bzw.
   Dev-Mode-Bypass-Login und statt des Klartext-Admin-Codes "Admin" in den
   Einstellungen). Dazu gehört auch der Entwicklermodus-Bypass, der selbst
   den letzten Haupt-Admin aus der Gruppe entfernen, ihm den
   Haupt-Admin-Status entziehen (MemberDetailView/UserRepository
   `bypassLastAdminGuard`) sowie beliebige Mitglieder/Vice-Admins direkt
   zu Haupt-Admin ernennen kann ("Zum Haupt-Admin machen") — bleibt bis
   dahin ein bewusster, nur im Entwicklermodus/via Admin-Vorschau
   erreichbarer Prototyp-Notausgang.
3. **Erledigt (2026-09-03):** QR-Code-Zugang für Apotheken ohne
   App-Installation: `web/index.html` zeigt dieselbe Ja/Nein-Frage wie
   PharmacySamplesView, Zuordnung über `SampleLocation.token` im Link.
   Schreibt NICHT direkt per CloudKit JS (das war der ursprüngliche Plan,
   ging aber nicht — die `_world`-Sicherheitsrolle lässt sich im CloudKit
   Dashboard nur auf Read setzen, Create/Write sind für anonyme Clients
   strukturell gesperrt), sondern über einen lokalen Python-Proxy
   (`web/proxy_server.py`), der per CloudKit-Server-to-Server-Key schreibt
   (siehe README.md "CloudKit-Setup"). Admin-Feature "Apotheken verwalten"
   (Einstellungen → Admin) legt Apotheken an und zeigt/teilt pro Apotheke
   den QR-Code. Live gegen echtes CloudKit getestet (Lesen + Schreiben über
   den Proxy funktionieren nachweislich Ende-zu-Ende).
4. **Robustheit der CloudKit-Anbindung (Proben-Bereich)** — von einer
   unabhängigen Verifikation am 2026-09-03 gefunden, bewusst nicht mehr in
   derselben Nacht behoben:
   - `PharmacySamplesView` (Apotheken-Selbstmelde-Bildschirm) und
     `OnboardingContainerView.joinAsPharmacy()` scheitern ohne klare
     Fehleranzeige/Ladezustand, wenn CloudKit/iCloud nicht erreichbar ist
     (`try?`-verschluckte Fehler) — vor der CloudKit-Umstellung war dieser
     Pfad rein lokal und konnte praktisch nicht fehlschlagen.
   - `SettingsView.cleanupPharmacyPreviewLocationIfNeeded()` (DevMode-
     Apotheken-Vorschau) löscht die Test-Location nur best-effort
     (`try?`) — schlägt der Netzwerk-Delete fehl, bleibt der Test-Datensatz
     dauerhaft und team-sichtbar im echten Proben-Tab stehen.
   - Weitere Stellen (`SamplesListView` u.a.) unterscheiden nicht zwischen
     "wirklich keine Daten" und "Laden fehlgeschlagen" — beides sieht in
     der UI gleich aus.
   - Read-then-write-Race beim Report-Upsert (App und Web-Proxy): zwei
     nahezu gleichzeitige Meldungen für dieselbe Apotheke+Tag können beide
     "existiert noch nicht" sehen und kollidieren (kein Datenverlust, aber
     eine der beiden Anfragen schlägt sichtbar fehl).
5. **Erledigt (2026-09-15):** Web-Passwort wurde im Klartext gespeichert
   und verglichen (`User.webPassword`). Behoben im Zuge des Web-App-Umbaus
   (app.mediproben.com, siehe README): Feld heißt jetzt
   `User.webPasswordHash`, gespeichert wird `SHA256(Pepper:Passwort)`
   (`WebPasswordHashing.swift` / `hashWebPassword` in
   `web/worker-app/src/index.js`, Pepper muss auf beiden Seiten identisch
   sein — `WebPasswordPepper.swift` bzw. Worker-Secret
   `WEB_PASSWORD_PEPPER`). `MemberDetailView` kann das gesetzte Passwort
   dadurch nicht mehr anzeigen/vorbefüllen, nur noch neu setzen oder
   entfernen.
6. **CloudKit-Umgebung der Web-Worker (Development vs. Production)** — beide
   Cloudflare Worker (`web/worker/`, `web/worker-app/`) sprechen aktuell
   bewusst `CLOUDKIT_ENVIRONMENT = "development"` an, nicht Production.
   Funktioniert für den aktuellen Test-/Entwicklungsstand, aber sobald echte
   Apotheken oder Team-Mitglieder über TestFlight/App Store (= Production)
   arbeiten, laufen App und Web-Worker gegen zwei getrennte Datenbanken.
   Muss vor einem echten Rollout bewusst entschieden und umgestellt werden
   (siehe README "CloudKit-Setup" Punkt 6) — auf Wunsch des Users am
   2026-09-15 explizit ins Backlog aufgenommen statt jetzt nebenbei
   entschieden.

   **Konkret bestätigt betroffen (2026-09-15):** Die Apotheke "Warendorf"
   wurde über die TestFlight-App angelegt (= Production). Ihr QR-Code
   funktioniert deshalb aktuell nicht — der Apotheken-Worker
   (`web/worker/`) fragt Development ab, findet den Token dort nicht, die
   Apotheke landet auf der Seite ohne eingeloggt zu werden. Kein Bug im
   QR-Code/Worker-Code selbst (beides verifiziert korrekt), reiner
   Umgebungs-Mismatch. Braucht zum Fixen: einen zweiten,
   production-spezifischen CloudKit-Server-to-Server-Key (Keys sind pro
   Umgebung getrennt) + `CLOUDKIT_ENVIRONMENT` in `web/worker/wrangler.toml`
   auf `"production"` umstellen.
7. (Platz für weitere Punkte, die im Gesprächsverlauf mit "Backlog:"
   markiert werden.)
