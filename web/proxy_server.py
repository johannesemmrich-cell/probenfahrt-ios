#!/usr/bin/env python3
"""Serves the Apotheken-Check-in-Seite (nur index.html — siehe ALLOWED_PATHS,
NICHT der ganze Ordnerinhalt!) UND eine kleine JSON-API, die über einen
CloudKit-Server-to-Server-Key im Namen der Webseite schreibt (siehe
cloudkit_client.py für das Warum).

Start: python3 proxy_server.py [port]  (Default 8080)
"""
import http.server
import json
import socketserver
import sys
import urllib.parse
import uuid
from datetime import datetime

from cloudkit_client import CloudKitClient, CloudKitError

try:
    import server_config
except ImportError:
    print("FEHLER: web/server_config.py fehlt. Kopiere server_config.example.py zu server_config.py und trage deinen CloudKit-Key ein.")
    sys.exit(1)

# Nur diese Pfade werden als statische Datei ausgeliefert — bewusste
# Allowlist statt SimpleHTTPRequestHandlers Default-Verhalten (liefert
# sonst JEDE Datei im Arbeitsverzeichnis aus, inkl. eckey.pem/
# server_config.py mit dem privaten CloudKit-Key!).
ALLOWED_STATIC_PATHS = {"/", "/index.html"}


def today_local():
    now = datetime.now().astimezone()
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def report_record_name(location_id, day):
    return f"report-{location_id}-{day.strftime('%Y-%m-%d')}"


class Handler(http.server.SimpleHTTPRequestHandler):
    def _client(self):
        return CloudKitClient(
            server_config.CONTAINER_IDENTIFIER,
            server_config.ENVIRONMENT,
            server_config.KEY_ID,
            server_config.PRIVATE_KEY_PATH,
        )

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/pharmacy":
            return self._handle_get_pharmacy(parsed)
        if parsed.path in ALLOWED_STATIC_PATHS:
            self.path = "/index.html"
            return super().do_GET()
        self.send_error(404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/report":
            return self._handle_post_report()
        self.send_error(404)

    def _handle_get_pharmacy(self, parsed):
        params = urllib.parse.parse_qs(parsed.query)
        token = (params.get("token") or [""])[0]
        if not token:
            return self._send_json(400, {"error": "token fehlt"})
        try:
            client = self._client()
            location = client.find_location_by_token(token)
            if not location:
                return self._send_json(404, {"error": "Unbekannter Apotheken-Code"})
            record_name = report_record_name(location["id"], today_local())
            report = client.get_report(record_name)
            self._send_json(200, {
                "location": location,
                "hasSamples": report["hasSamples"] if report else None,
            })
        except CloudKitError as e:
            self._send_json(502, {"error": str(e), "detail": e.detail})
        except Exception as e:  # noqa: BLE001 - surfaced to the page for debugging tonight
            self._send_json(500, {"error": str(e)})

    def _handle_post_report(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
            token = payload["token"]
            has_samples = bool(payload["hasSamples"])
        except (KeyError, ValueError, json.JSONDecodeError):
            return self._send_json(400, {"error": "Ungültige Anfrage"})

        try:
            client = self._client()
            # locationID/groupID kommen NIE vom Client — nur der Token
            # entscheidet, welche Apotheke gemeint ist (per CloudKit
            # nachgeschlagen), sonst könnte jeder mit einer beliebigen
            # locationID Meldungen für fremde Apotheken fälschen.
            location = client.find_location_by_token(token)
            if not location:
                return self._send_json(404, {"error": "Unbekannter Apotheken-Code"})
            day = today_local()
            record_name = report_record_name(location["id"], day)
            existing = client.get_report(record_name)
            fields = {
                "reportID": {"value": str(uuid.uuid4()), "type": "STRING"},
                "locationID": {"value": location["id"], "type": "STRING"},
                "day": {"value": int(day.timestamp() * 1000), "type": "TIMESTAMP"},
                "hasSamples": {"value": 1 if has_samples else 0, "type": "INT64"},
                "statusNote": {"value": "", "type": "STRING"},
                "reportedAt": {"value": int(datetime.now().timestamp() * 1000), "type": "TIMESTAMP"},
            }
            if location.get("groupID"):
                fields["groupID"] = {"value": location["groupID"], "type": "STRING"}
            client.save_report(record_name, fields, exists=existing is not None)
            self._send_json(200, {"ok": True, "hasSamples": has_samples})
        except CloudKitError as e:
            self._send_json(502, {"error": str(e), "detail": e.detail})
        except Exception as e:  # noqa: BLE001 - surfaced to the page for debugging tonight
            self._send_json(500, {"error": str(e)})


class ThreadingHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with ThreadingHTTPServer(("0.0.0.0", port), Handler) as httpd:
        print(f"Probenfahrt Apotheken-Check-in (mit CloudKit-Proxy) läuft auf Port {port}")
        httpd.serve_forever()
