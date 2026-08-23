# Backlog

Neue Einträge werden hier NUR ergänzt, wenn im Chat explizit "Backlog:" oder
"ins Backlog" gesagt wird. Andere Ideen/offene Punkte, die während der
Entwicklung auffallen, werden im Chat angesprochen statt automatisch hier
ergänzt.

1. Echte Backend-/Datenbank-Anbindung (z.B. Supabase/Firebase oder CloudKit-
   Sync) für echte Mehrbenutzer-Synchronisierung, als Ersatz für die lokale
   SwiftData-Mock-Schicht.
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
3. **[Hohe Priorität]** QR-Code-Zugang für Apotheken ohne App-Installation:
   Apotheke scannt einen apothekenspezifischen QR-Code und landet auf einer
   schlanken Webseite mit derselben Ja/Nein-Frage wie PharmacySamplesView
   ("Habt ihr heute Proben?") — kein Download, kein Account nötig,
   Zuordnung läuft über einen eindeutigen Token pro Apotheke im Link. Setzt
   Punkt 1 (echtes Backend) voraus, da die Web-Eingabe sonst nirgendwo
   landet, wo das Laborteam-iPhone sie sieht. Pro Apotheke muss außerdem ein
   eigener QR-Code generierbar (und ausdruckbar/aushändigbar) sein,
   vermutlich als Admin-Feature.
4. (Platz für weitere Punkte, die im Gesprächsverlauf mit "Backlog:"
   markiert werden.)
