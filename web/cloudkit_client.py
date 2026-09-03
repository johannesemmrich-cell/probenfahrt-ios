"""Minimal CloudKit Web Services client using Server-to-Server auth.

The CloudKit Dashboard's `_world` security role only allows Read via the
UI — Create/Write are structurally disabled for anonymous/unauthenticated
clients, so writing from the check-in webpage can't go through CloudKit JS
with just an API token (that only works for Read). A Server-to-Server key
is Apple's documented mechanism for exactly this case: a backend writes to
CloudKit on behalf of users who never sign in with an Apple ID.

Request signing per Apple's CloudKit Web Services reference:
  message = "{ISO8601 date}:{base64(SHA256(body))}:{request path}"
  signature = base64(ECDSA-P256-SHA256(message, private key))
sent as the X-Apple-CloudKit-Request-* headers below.
"""
import base64
import hashlib
import json
import urllib.error
import urllib.request
from datetime import datetime, timezone

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


class CloudKitError(Exception):
    def __init__(self, message, detail=None):
        super().__init__(message)
        self.detail = detail


class CloudKitClient:
    HOST = "https://api.apple-cloudkit.com"

    def __init__(self, container_identifier, environment, key_id, private_key_path):
        self.container_identifier = container_identifier
        self.environment = environment
        self.key_id = key_id
        with open(private_key_path, "rb") as f:
            self.private_key = serialization.load_pem_private_key(f.read(), password=None)

    def _database_path(self, operation):
        return f"/database/1/{self.container_identifier}/{self.environment}/public/{operation}"

    def _sign_and_post(self, path, body_dict):
        body_bytes = json.dumps(body_dict).encode("utf-8")
        date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        body_hash = base64.b64encode(hashlib.sha256(body_bytes).digest()).decode("utf-8")
        message = f"{date}:{body_hash}:{path}".encode("utf-8")
        signature = self.private_key.sign(message, ec.ECDSA(hashes.SHA256()))
        signature_b64 = base64.b64encode(signature).decode("utf-8")

        request = urllib.request.Request(
            self.HOST + path,
            data=body_bytes,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "X-Apple-CloudKit-Request-KeyID": self.key_id,
                "X-Apple-CloudKit-Request-ISO8601Date": date,
                "X-Apple-CloudKit-Request-SignatureV1": signature_b64,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise CloudKitError(f"CloudKit HTTP {error.code}", detail=detail)

    def find_location_by_token(self, token):
        body = {
            "query": {
                "recordType": "SampleLocation",
                "filterBy": [
                    {"fieldName": "token", "comparator": "EQUALS", "fieldValue": {"value": token, "type": "STRING"}}
                ],
            }
        }
        result = self._sign_and_post(self._database_path("records/query"), body)
        records = result.get("records", [])
        if not records or "fields" not in records[0]:
            return None
        fields = records[0]["fields"]
        return {
            "id": fields["locationID"]["value"],
            "groupID": fields.get("groupID", {}).get("value"),
            "name": fields["name"]["value"],
        }

    def get_report(self, record_name):
        body = {"records": [{"recordName": record_name}]}
        result = self._sign_and_post(self._database_path("records/lookup"), body)
        records = result.get("records", [])
        if not records or "fields" not in records[0]:
            return None
        return {"hasSamples": records[0]["fields"]["hasSamples"]["value"] == 1}

    def save_report(self, record_name, fields, exists):
        operation_type = "forceUpdate" if exists else "create"
        record = {"recordName": record_name, "recordType": "SampleReport", "fields": fields}
        body = {"operations": [{"operationType": operation_type, "record": record}]}
        result = self._sign_and_post(self._database_path("records/modify"), body)
        records = result.get("records", [])
        if records and records[0].get("serverErrorCode"):
            raise CloudKitError(records[0].get("reason", "Unbekannter CloudKit-Fehler"))
        return result
