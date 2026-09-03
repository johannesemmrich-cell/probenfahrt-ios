# Kopiere diese Datei zu server_config.py (wird nicht committed, siehe
# .gitignore) und trage den Key aus dem CloudKit Dashboard ein:
# API Access -> Server-to-Server Keys -> neuen Key erzeugen, dabei den
# Public Key aus eckey.pem einfügen (siehe README.md).

CONTAINER_IDENTIFIER = "iCloud.com.johannesemmrich.probenfahrt"
# 'development', solange das CloudKit-Schema noch nicht nach Production
# deployed wurde. Vor dem echten TestFlight-Rollout auf 'production'
# umstellen (und im Dashboard "Deploy Schema Changes" ausführen).
ENVIRONMENT = "development"
KEY_ID = "DEIN_KEY_ID_HIER"
PRIVATE_KEY_PATH = "eckey.pem"
