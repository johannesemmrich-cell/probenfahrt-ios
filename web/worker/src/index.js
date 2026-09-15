/**
 * Cloudflare-Worker-Portierung von web/proxy_server.py + web/cloudkit_client.py.
 * Gleiches Protokoll, gleiche Endpunkte (/api/pharmacy, /api/report), gleiche
 * CloudKit-Server-to-Server-Auth - nur die Laufzeitumgebung ist anders
 * (läuft bei Cloudflare statt auf einem eigenen Server/Mac).
 *
 * Wichtiger Unterschied zur Python-Version: die Web Crypto API (die einzige
 * Krypto-API, die in Workers verfügbar ist) liefert ECDSA-Signaturen im
 * rohen IEEE-P1363-Format (r || s, je 32 Byte), aber Apples CloudKit Web
 * Services erwarten DER-kodierte Signaturen (wie sie Python/OpenSSL/Node
 * standardmäßig erzeugen) - siehe derEncodeSignature() unten.
 */

const CLOUDKIT_HOST = "https://api.apple-cloudkit.com";

function databasePath(env, operation) {
  return `/database/1/${env.CONTAINER_IDENTIFIER}/${env.CLOUDKIT_ENVIRONMENT}/public/${operation}`;
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes) {
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

async function signAndPost(env, path, bodyObject) {
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

async function findLocationByToken(env, token) {
  const body = {
    query: {
      recordType: "SampleLocation",
      filterBy: [
        { fieldName: "token", comparator: "EQUALS", fieldValue: { value: token, type: "STRING" } },
      ],
    },
  };
  const result = await signAndPost(env, databasePath(env, "records/query"), body);
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  const fields = records[0].fields;
  return {
    id: fields.locationID.value,
    groupID: fields.groupID ? fields.groupID.value : null,
    name: fields.name.value,
  };
}

/**
 * Web-only login (no QR code / token): an admin assigns each team member an
 * optional password in the app (MemberDetailView) so they can identify
 * themselves here without scanning anything. Deliberately no session/cookie
 * yet and no functionality beyond the greeting - see BACKLOG/chat, this is
 * step one of a feature that's still being scoped out.
 */
async function findUserByPassword(env, password) {
  const body = {
    query: {
      recordType: "User",
      filterBy: [
        { fieldName: "webPassword", comparator: "EQUALS", fieldValue: { value: password, type: "STRING" } },
      ],
    },
  };
  const result = await signAndPost(env, databasePath(env, "records/query"), body);
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  const fields = records[0].fields;
  return {
    name: fields.name ? fields.name.value : "",
    abbreviation: fields.abbreviation ? fields.abbreviation.value : "",
  };
}

function reportRecordName(locationId, day) {
  const iso = day.toISOString().slice(0, 10);
  return `report-${locationId}-${iso}`;
}

async function getReport(env, recordName) {
  const body = { records: [{ recordName }] };
  const result = await signAndPost(env, databasePath(env, "records/lookup"), body);
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  return { hasSamples: records[0].fields.hasSamples.value === 1 };
}

async function saveReport(env, recordName, fields, exists) {
  const record = { recordName, recordType: "SampleReport", fields };
  const body = { operations: [{ operationType: exists ? "forceUpdate" : "create", record }] };
  const result = await signAndPost(env, databasePath(env, "records/modify"), body);
  const records = result.records || [];
  if (records.length && records[0].serverErrorCode) {
    throw new Error(records[0].reason || "Unbekannter CloudKit-Fehler");
  }
  return result;
}

/**
 * The lab team is in Germany, so "today" must be the Berlin calendar day,
 * not the Worker runtime's UTC day - naively using getUTCFullYear/Month/Date
 * shifts the date for 1-2 hours around midnight (depending on DST) and can
 * make a check-in overwrite yesterday's report instead of creating today's.
 * Intl.DateTimeFormat resolves the correct Berlin Y/M/D (DST-aware) without
 * manual offset math, then Date.UTC anchors it at UTC midnight so
 * toISOString().slice(0,10) reliably reproduces that same Y-M-D string -
 * matching CloudKitQuerying.localDayString's format on the app side.
 */
function todayLocal() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const lookup = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return new Date(Date.UTC(Number(lookup.year), Number(lookup.month) - 1, Number(lookup.day)));
}

function jsonResponse(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleGetPharmacy(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") || "";
  if (!token) return jsonResponse(400, { error: "token fehlt" });
  try {
    const location = await findLocationByToken(env, token);
    if (!location) return jsonResponse(404, { error: "Unbekannter Apotheken-Code" });
    const recordName = reportRecordName(location.id, todayLocal());
    const report = await getReport(env, recordName);
    return jsonResponse(200, { location, hasSamples: report ? report.hasSamples : null });
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostReport(request, env) {
  let token, hasSamples;
  try {
    const payload = await request.json();
    token = payload.token;
    hasSamples = Boolean(payload.hasSamples);
    if (!token) throw new Error("token fehlt");
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    // locationID/groupID kommen nie vom Client, nur der Token entscheidet,
    // welche Apotheke gemeint ist - siehe proxy_server.py für die Begründung.
    const location = await findLocationByToken(env, token);
    if (!location) return jsonResponse(404, { error: "Unbekannter Apotheken-Code" });
    const day = todayLocal();
    const recordName = reportRecordName(location.id, day);
    const existing = await getReport(env, recordName);
    const fields = {
      reportID: { value: crypto.randomUUID(), type: "STRING" },
      locationID: { value: location.id, type: "STRING" },
      day: { value: day.getTime(), type: "TIMESTAMP" },
      hasSamples: { value: hasSamples ? 1 : 0, type: "INT64" },
      statusNote: { value: "", type: "STRING" },
      reportedAt: { value: Date.now(), type: "TIMESTAMP" },
    };
    if (location.groupID) fields.groupID = { value: location.groupID, type: "STRING" };
    await saveReport(env, recordName, fields, existing !== null);
    return jsonResponse(200, { ok: true, hasSamples });
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostLogin(request, env) {
  let password;
  try {
    const payload = await request.json();
    password = payload.password;
    if (!password) throw new Error("password fehlt");
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    const user = await findUserByPassword(env, password);
    if (!user) {
      // No account lockout/CAPTCHA yet (see BACKLOG/chat) - this delay is a
      // cheap, stateless speed bump against naive scripted brute-forcing,
      // not real rate limiting.
      await sleep(1000);
      return jsonResponse(401, { error: "Falsches Passwort" });
    }
    return jsonResponse(200, user);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/api/pharmacy") {
      return handleGetPharmacy(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/report") {
      return handlePostReport(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/login") {
      return handlePostLogin(request, env);
    }
    // Alles andere (/, /index.html, ...) wird schon automatisch von den
    // Workers Static Assets aus public/ ausgeliefert, bevor dieser Fetch-
    // Handler überhaupt läuft - dieser Fall greift nur für unbekannte Pfade.
    return new Response("Not found", { status: 404 });
  },
};
