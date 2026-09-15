/**
 * Gemeinsame CloudKit-Server-to-Server-Anbindung für alle Cloudflare Worker
 * dieses Projekts (aktuell: web/worker = Apotheken-Check-in, web/worker-app =
 * Team-Web-App). Portierung von web/proxy_server.py + web/cloudkit_client.py.
 *
 * Wichtiger Unterschied zur Python-Version: die Web Crypto API (die einzige
 * Krypto-API, die in Workers verfügbar ist) liefert ECDSA-Signaturen im
 * rohen IEEE-P1363-Format (r || s, je 32 Byte), aber Apples CloudKit Web
 * Services erwarten DER-kodierte Signaturen (wie sie Python/OpenSSL/Node
 * standardmäßig erzeugen) - siehe derEncodeSignature() unten.
 */

export const CLOUDKIT_HOST = "https://api.apple-cloudkit.com";

export function databasePath(env, operation) {
  return `/database/1/${env.CONTAINER_IDENTIFIER}/${env.CLOUDKIT_ENVIRONMENT}/public/${operation}`;
}

export function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function bytesToBase64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

/** Strips a leading 0x00 pad byte, or adds one if the high bit is set (DER INTEGERs are signed). */
function toDerInteger(bytes) {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  let trimmed = bytes.slice(i);
  if (trimmed[0] & 0x80) {
    const padded = new Uint8Array(trimmed.length + 1);
    padded.set(trimmed, 1);
    trimmed = padded;
  }
  return trimmed;
}

/** Converts Web Crypto's raw (r||s) P-256 ECDSA signature into the DER SEQUENCE{INTEGER,INTEGER} CloudKit expects. */
function derEncodeSignature(rawSignature) {
  const bytes = new Uint8Array(rawSignature);
  const r = toDerInteger(bytes.slice(0, 32));
  const s = toDerInteger(bytes.slice(32, 64));
  const rField = new Uint8Array([0x02, r.length, ...r]);
  const sField = new Uint8Array([0x02, s.length, ...s]);
  const body = new Uint8Array([...rField, ...sField]);
  return new Uint8Array([0x30, body.length, ...body]);
}

async function importPrivateKey(pkcs8Base64) {
  const keyBytes = base64ToBytes(pkcs8Base64);
  return crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

export async function signAndPost(env, path, bodyObject) {
  const bodyBytes = new TextEncoder().encode(JSON.stringify(bodyObject));
  const date = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const bodyHashBuffer = await crypto.subtle.digest("SHA-256", bodyBytes);
  const bodyHashBase64 = bytesToBase64(new Uint8Array(bodyHashBuffer));
  const message = new TextEncoder().encode(`${date}:${bodyHashBase64}:${path}`);

  const privateKey = await importPrivateKey(env.CLOUDKIT_PRIVATE_KEY_PKCS8_BASE64);
  const rawSignature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    message
  );
  const signatureBase64 = bytesToBase64(derEncodeSignature(rawSignature));

  const response = await fetch(CLOUDKIT_HOST + path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": env.CLOUDKIT_KEY_ID,
      "X-Apple-CloudKit-Request-ISO8601Date": date,
      "X-Apple-CloudKit-Request-SignatureV1": signatureBase64,
    },
    body: bodyBytes,
  });

  const json = await response.json();
  if (!response.ok) {
    const error = new Error(`CloudKit HTTP ${response.status}`);
    error.detail = JSON.stringify(json);
    throw error;
  }
  return json;
}

/**
 * Pages through `continuationMarker` until all matching records are
 * collected - CloudKit caps a single query response's result count, same
 * reason CloudKitQuerying.allRecords pages on the app side.
 */
export async function queryAllRecords(env, queryBody) {
  let records = [];
  let continuationMarker;
  do {
    const body = continuationMarker ? { ...queryBody, continuationMarker } : queryBody;
    const result = await signAndPost(env, databasePath(env, "records/query"), body);
    records = records.concat(result.records || []);
    continuationMarker = result.continuationMarker;
  } while (continuationMarker);
  return records;
}
