#!/bin/sh
# Startet die Apotheken-Check-in-Seite lokal, inkl. CloudKit-Proxy
# (proxy_server.py) für die Schreibzugriffe per Server-to-Server-Key.
# Siehe README.md für den kompletten CloudKit-Dashboard-Setup, der davor
# einmalig nötig ist (inkl. server_config.py aus server_config.example.py
# anlegen und den Key eintragen).
#
# Für echtes Scannen per Handy im selben WLAN: nicht die "localhost"-URL
# verwenden, sondern die unten ausgegebene LAN-IP — und dieselbe LAN-IP
# auch als Basis-URL in der App (Apotheken verwalten → Apotheke → Web-
# Adresse für QR-Codes) eintragen, bevor QR-Codes generiert werden.

PORT="${1:-8080}"
cd "$(dirname "$0")" || exit 1

if [ ! -f server_config.py ]; then
  echo "FEHLER: web/server_config.py fehlt."
  echo "Kopiere server_config.example.py zu server_config.py und trage deinen CloudKit-Server-to-Server-Key ein (siehe README.md)."
  exit 1
fi

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

echo "Probenfahrt Apotheken-Check-in läuft auf:"
echo "  http://localhost:${PORT}"
if [ -n "$LAN_IP" ]; then
  echo "  http://${LAN_IP}:${PORT}   (für Scans von einem echten Handy im selben WLAN)"
fi
echo ""
echo "Zum Beenden: Ctrl+C"
echo ""

python3 proxy_server.py "$PORT"
