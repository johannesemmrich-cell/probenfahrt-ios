/**
 * Cloudflare Worker für die Team-Web-App unter app.mediproben.com - komplett
 * getrennt vom Apotheken-QR-Check-in (web/worker/, mediproben.com). Login
 * läuft NICHT über CloudKit-Sessions/Apple-ID, sondern über ein von einem
 * Admin pro Mitglied vergebenes Passwort (MemberDetailView) plus ein
 * selbst signiertes Session-Cookie - siehe README für die Begründung.
 */

import { databasePath, signAndPost, queryAllRecords, base64ToBytes, bytesToBase64 } from "../../shared/cloudkit.js";

const SESSION_COOKIE_NAME = "session";
// Kein Self-Service-Passwort-Reset vorgesehen - eine kurze TTL würde nur
// unnötige Login-Reibung erzeugen, deshalb lang und bei jedem gültigen
// Request gleitend verlängert (siehe attachRefreshedSession).
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;

function jsonResponse(status, payload, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...extraHeaders },
  });
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function base64UrlEncode(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str) {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/**
 * Muss byte-für-byte identisch zu WebPasswordEncryption in
 * Probenfahrt/Support/WebPasswordEncryption.swift sein (AES-256-GCM,
 * IV deterministisch aus SHA256("iv:"+key+":"+password) abgeleitet statt
 * zufällig - damit bleibt "gleiches Passwort -> gleicher Chiffretext"
 * erhalten, nötig für die Exact-Match-Query in findUserByEncryptedPassword/
 * isWebPasswordTaken. Format: IV (12 Byte) || Ciphertext+Tag, base64 -
 * entspricht CryptoKits AES.GCM.SealedBox.combined-Layout. Cross-Kompatibilität
 * mit einem Swift-Testvektor verifiziert (WebPasswordEncryptionTests.swift).
 */
async function aesKey(env) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(env.WEB_PASSWORD_ENCRYPTION_KEY));
  return crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

async function derivedIv(env, password) {
  const input = `iv:${env.WEB_PASSWORD_ENCRYPTION_KEY}:${password}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return new Uint8Array(digest).slice(0, 12);
}

async function encryptWebPassword(env, password) {
  const key = await aesKey(env);
  const iv = await derivedIv(env, password);
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(password));
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return bytesToBase64(combined);
}

async function decryptWebPassword(env, encoded) {
  const combined = base64ToBytes(encoded);
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const key = await aesKey(env);
  const plaintextBuffer = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
  return new TextDecoder().decode(plaintextBuffer);
}

async function findUserByEncryptedPassword(env, encrypted) {
  const body = {
    query: {
      recordType: "User",
      filterBy: [
        { fieldName: "webPasswordEncrypted", comparator: "EQUALS", fieldValue: { value: encrypted, type: "STRING" } },
      ],
    },
  };
  const result = await signAndPost(env, databasePath(env, "records/query"), body);
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  const fields = records[0].fields;
  return {
    id: fields.userID ? fields.userID.value : null,
    groupID: fields.groupID ? fields.groupID.value : null,
    role: fields.role ? fields.role.value : "member",
    name: fields.name ? fields.name.value : "",
    abbreviation: fields.abbreviation ? fields.abbreviation.value : "",
  };
}

async function hmacKey(env) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.SESSION_HMAC_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

async function createSessionCookie(env, user) {
  const payload = {
    uid: user.id,
    gid: user.groupID,
    role: user.role,
    name: user.name,
    abbr: user.abbreviation,
    dev: user.dev === true,
    exp: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS,
  };
  const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const key = await hmacKey(env);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payloadB64));
  const sigB64 = base64UrlEncode(new Uint8Array(signature));
  return `${SESSION_COOKIE_NAME}=${payloadB64}.${sigB64}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL_SECONDS}`;
}

function clearedSessionCookie() {
  return `${SESSION_COOKIE_NAME}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`;
}

/**
 * Host-only gesetzt (kein Domain-Attribut) - dadurch strikt auf
 * app.mediproben.com beschränkt, obwohl es technisch eine Subdomain von
 * mediproben.com ist. Landet nie beim Apotheken-Worker.
 */
async function verifySession(request, env) {
  const cookieHeader = request.headers.get("Cookie") || "";
  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${SESSION_COOKIE_NAME}=([^;]+)`));
  if (!match) return null;
  const [payloadB64, sigB64] = match[1].split(".");
  if (!payloadB64 || !sigB64) return null;

  // Ein manipuliertes oder beschädigtes Cookie (falsche Base64-Länge o.ä.)
  // lässt base64UrlDecode/verify werfen statt sauber false zurückzugeben -
  // ohne try/catch würde das hier eine 500 statt einer 401 produzieren.
  try {
    const key = await hmacKey(env);
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      base64UrlDecode(sigB64),
      new TextEncoder().encode(payloadB64)
    );
    if (!valid) return null;

    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadB64)));
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

/**
 * session.dev (nur via Dev-Passwort-Login gesetzt, siehe handlePostLogin)
 * gibt automatisch volle Admin-Rechte - Pendant zu DevModeStore.isAdminPreviewActive
 * in EffectiveAdmin.swift, nur ohne den nativen Zwischenschritt (dort muss
 * man Entwicklermodus zusätzlich noch manuell auf "Alle Admin-Rechte"
 * stellen - hier auf User-Wunsch direkt automatisch beim Dev-Login).
 */
function isAdminSession(session) {
  return session.dev === true || session.role === "admin" || session.role === "viceAdmin";
}

/** Strikter als isAdminSession (schließt viceAdmin aus) - Pendant zu isFullAdmin in EffectiveAdmin.swift. */
function isFullAdminSession(session) {
  return session.dev === true || session.role === "admin";
}

async function attachRefreshedSession(response, env, session) {
  const cookie = await createSessionCookie(env, {
    id: session.uid,
    groupID: session.gid,
    role: session.role,
    name: session.name,
    abbreviation: session.abbr,
    dev: session.dev === true,
  });
  response.headers.set("Set-Cookie", cookie);
  return response;
}

/**
 * Gleicher Hash wie DevPassword.swift (SHA-256, ungesalzen, das Passwort
 * selbst wird nirgends gespeichert) - Pendant zum Dev-Mode-Bypass im
 * Onboarding: dasselbe Passwort loggt hier direkt als "Entwickler"/"DEV"
 * in der LABOR2026-Testgruppe ein, ohne eigenes Web-Passwort nötig zu haben.
 */
const DEV_PASSWORD_HASH = "5187f60ecb928fbbdfd417d75bda193f441dce05a2309f7494770a584f59e27e";
const DEV_TEST_GROUP_JOIN_CODE = "labor2026"; // MockDataSeeder.testGroupJoinCode, lowercased wie beim normalen Beitritt

async function matchesDevPassword(input) {
  const trimmed = (input || "").trim();
  if (!trimmed) return false;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(trimmed));
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === DEV_PASSWORD_HASH;
}

async function findGroupIDByJoinCode(env, joinCode) {
  const body = {
    query: {
      recordType: "TeamGroup",
      filterBy: [
        { fieldName: "joinCode", comparator: "EQUALS", fieldValue: { value: joinCode, type: "STRING" } },
      ],
    },
  };
  const result = await signAndPost(env, databasePath(env, "records/query"), body);
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  return records[0].fields.groupID ? records[0].fields.groupID.value : null;
}

/**
 * abbreviation ist bei User NICHT Queryable (nur groupID/webPasswordEncrypted,
 * siehe README) - deshalb wie sonst auch: Gruppe komplett holen und hier
 * filtern statt gezielt abzufragen.
 */
async function findOrCreateDevUser(env) {
  const groupID = await findGroupIDByJoinCode(env, DEV_TEST_GROUP_JOIN_CODE);
  if (!groupID) return null;

  const users = await findUsersForGroup(env, groupID);
  const existing = users.find((u) => u.abbreviation.toUpperCase() === "DEV");
  if (existing) {
    return { id: existing.id, groupID: groupID, role: existing.role, name: existing.name, abbreviation: existing.abbreviation };
  }

  const userID = crypto.randomUUID();
  const fields = {
    userID: { value: userID, type: "STRING" },
    name: { value: "Entwickler", type: "STRING" },
    abbreviation: { value: "DEV", type: "STRING" },
    role: { value: "member", type: "STRING" },
    accountKind: { value: "labTeam", type: "STRING" },
    groupID: { value: groupID, type: "STRING" },
    createdAt: { value: Date.now(), type: "TIMESTAMP" },
    webPasswordEncrypted: { value: "", type: "STRING" },
  };
  await signAndPost(env, databasePath(env, "records/modify"), {
    operations: [{ operationType: "create", record: { recordName: `user-${userID}`, recordType: "User", fields } }],
  });
  return { id: userID, groupID: groupID, role: "member", name: "Entwickler", abbreviation: "DEV" };
}

async function handlePostLogin(request, env) {
  let password;
  try {
    const payload = await request.json();
    password = (payload.password || "").trim();
    if (!password) throw new Error("password fehlt");
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    if (await matchesDevPassword(password)) {
      const devUser = await findOrCreateDevUser(env);
      if (!devUser) return jsonResponse(401, { error: "Dev-Gruppe nicht gefunden." });
      devUser.dev = true;
      const cookie = await createSessionCookie(env, devUser);
      return jsonResponse(
        200,
        { name: devUser.name, abbreviation: devUser.abbreviation, role: devUser.role },
        { "Set-Cookie": cookie }
      );
    }

    const encrypted = await encryptWebPassword(env, password);
    const user = await findUserByEncryptedPassword(env, encrypted);
    if (!user || !user.id) {
      // Kein Account-Lockout/CAPTCHA (siehe BACKLOG #5) - diese Verzögerung
      // ist nur ein billiger, zustandsloser Bremsklotz gegen naive
      // Skript-Angriffe, kein echtes Rate-Limiting.
      await sleep(1000);
      return jsonResponse(401, { error: "Falsches Passwort" });
    }
    const cookie = await createSessionCookie(env, user);
    return jsonResponse(
      200,
      { name: user.name, abbreviation: user.abbreviation, role: user.role },
      { "Set-Cookie": cookie }
    );
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostLogout() {
  return jsonResponse(200, { ok: true }, { "Set-Cookie": clearedSessionCookie() });
}

async function handleGetMe(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  const response = jsonResponse(200, {
    id: session.uid,
    name: session.name,
    abbreviation: session.abbr,
    role: session.role,
    isAdmin: isAdminSession(session),
    isDev: session.dev === true,
  });
  return attachRefreshedSession(response, env, session);
}

// MARK: - Umfragen/Kalender (SurveyDay/SurveyEntry, siehe
// CloudKitSurveyRepository.swift - gleiche Feldnamen, gleiches
// Record-ID-Schema, damit App und Web-App dieselben Records sehen)

function berlinDateString(ms) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(ms));
  const lookup = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${lookup.year}-${lookup.month}-${lookup.day}`;
}

/** DST-genau (CET/CEST) - liefert die Berlin-Mitternacht des gegebenen Tages als Epoch-ms. */
function berlinMidnightMs(dateString) {
  const [y, m, d] = dateString.split("-").map(Number);
  const utcGuess = Date.UTC(y, m - 1, d);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(new Date(utcGuess));
  const hourInBerlin = Number(parts.find((p) => p.type === "hour").value.replace("24", "0"));
  return utcGuess - hourInBerlin * 60 * 60 * 1000;
}

function addDaysToDateString(dateString, days) {
  const [y, m, d] = dateString.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** Montag=2 ... Donnerstag=5 in JS' getUTCDay() (0=Sonntag) heißt 1..4. */
function isMondayThroughThursday(dateString) {
  const [y, m, d] = dateString.split("-").map(Number);
  const weekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return weekday >= 1 && weekday <= 4;
}

async function findSurveyDaysInRange(env, groupID, fromDateString, toDateString) {
  // 6h Puffer deckt jede Berlin-UTC-Abweichung (+1/+2h) sicher ab - danach
  // wird per berlinDateString exakt auf den Kalendertag nachgefiltert.
  const PAD_MS = 6 * 60 * 60 * 1000;
  const fromMs = Date.parse(`${fromDateString}T00:00:00Z`) - PAD_MS;
  const toMs = Date.parse(`${toDateString}T00:00:00Z`) + 24 * 60 * 60 * 1000 + PAD_MS;
  const body = {
    query: {
      recordType: "SurveyDay",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
        { fieldName: "date", comparator: "GREATER_THAN_OR_EQUALS", fieldValue: { value: fromMs, type: "TIMESTAMP" } },
        { fieldName: "date", comparator: "LESS_THAN_OR_EQUALS", fieldValue: { value: toMs, type: "TIMESTAMP" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records
    .map((r) => ({
      id: r.fields.dayID.value,
      date: berlinDateString(r.fields.date.value),
      isLocked: r.fields.isLocked ? r.fields.isLocked.value === 1 : false,
      lockReason: r.fields.lockReason ? r.fields.lockReason.value : null,
    }))
    .filter((day) => day.date >= fromDateString && day.date <= toDateString);
}

/** Legt fehlende Mo-Do-Tage im Bereich an - Pendant zu ensureDaysExist in CloudKitSurveyRepository.swift. */
async function ensureSurveyDaysExist(env, groupID, fromDateString, toDateString, existingDays) {
  const existingDates = new Set(existingDays.map((d) => d.date));
  let cursor = fromDateString;
  while (cursor <= toDateString) {
    if (isMondayThroughThursday(cursor) && !existingDates.has(cursor)) {
      const dayID = crypto.randomUUID();
      const record = {
        recordName: `surveyday-${groupID}-${cursor}`,
        recordType: "SurveyDay",
        fields: {
          dayID: { value: dayID, type: "STRING" },
          groupID: { value: groupID, type: "STRING" },
          date: { value: berlinMidnightMs(cursor), type: "TIMESTAMP" },
          isLocked: { value: 0, type: "INT64" },
        },
      };
      // Best-effort wie im App-Pendant: zwei gleichzeitige Anfragen für
      // denselben fehlenden Tag können auf dieselbe deterministische ID
      // race'n - eine der beiden create-Operationen schlägt dann sichtbar
      // fehl, aber es entsteht kein Duplikat.
      try {
        await signAndPost(env, databasePath(env, "records/modify"), {
          operations: [{ operationType: "create", record }],
        });
      } catch {
        // ignorieren, siehe Kommentar oben
      }
      existingDates.add(cursor);
    }
    cursor = addDaysToDateString(cursor, 1);
  }
}

async function findSurveyEntriesForDayIDs(env, groupID, dayIDs) {
  if (!dayIDs.length) return [];
  const body = {
    query: {
      recordType: "SurveyEntry",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  const dayIDSet = new Set(dayIDs);
  return records
    .map((r) => ({
      id: r.fields.entryID.value,
      dayID: r.fields.surveyDayID.value,
      userID: r.fields.userID.value,
      createdAt: r.fields.createdAt ? r.fields.createdAt.value : null,
    }))
    .filter((entry) => dayIDSet.has(entry.dayID));
}

/** Für Namen/Kürzel neben Einträgen - Entries kennen nur userID, keine Namen. */
async function findUsersForGroup(env, groupID) {
  const body = {
    query: {
      recordType: "User",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records.map((r) => ({
    id: r.fields.userID.value,
    name: r.fields.name ? r.fields.name.value : "",
    abbreviation: r.fields.abbreviation ? r.fields.abbreviation.value : "",
    role: r.fields.role ? r.fields.role.value : "member",
    accountKind: r.fields.accountKind ? r.fields.accountKind.value : "labTeam",
  }));
}

// MARK: - Profil (eigenes) + Mitglieder verwalten (User-Record-CRUD, siehe
// SettingsView.swift/TeamMembersView.swift/MemberDetailView.swift)

async function findUserRecordByUserID(env, groupID, userID) {
  const body = {
    query: {
      recordType: "User",
      filterBy: [
        { fieldName: "userID", comparator: "EQUALS", fieldValue: { value: userID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  const record = records.find((r) => r.fields.groupID && r.fields.groupID.value === groupID);
  if (!record) return null;
  return {
    recordName: record.recordName,
    id: record.fields.userID.value,
    name: record.fields.name ? record.fields.name.value : "",
    abbreviation: record.fields.abbreviation ? record.fields.abbreviation.value : "",
    role: record.fields.role ? record.fields.role.value : "member",
    accountKind: record.fields.accountKind ? record.fields.accountKind.value : "labTeam",
    groupID: record.fields.groupID ? record.fields.groupID.value : null,
    createdAt: record.fields.createdAt ? record.fields.createdAt.value : Date.now(),
    webPasswordEncrypted: (record.fields.webPasswordEncrypted && record.fields.webPasswordEncrypted.value) || null,
  };
}

async function isAbbreviationTakenInGroup(env, groupID, abbreviation, excludingUserID) {
  const normalized = abbreviation.trim().toLowerCase();
  const users = await findUsersForGroup(env, groupID);
  return users.some((u) => u.id !== excludingUserID && u.abbreviation.toLowerCase() === normalized);
}

/**
 * Volles Feld-Set statt nur der geänderten Felder, siehe
 * handlePostSurveyDayLock für die Begründung. webPasswordEncrypted wird
 * IMMER mitgeschickt (leerer String statt Weglassen bei "kein Passwort") -
 * unklar/ungetestet, ob forceUpdate ein weggelassenes Feld unverändert lässt
 * oder löscht, das hier umgeht die Frage.
 */
async function saveUserRecord(env, record) {
  const fields = {
    userID: { value: record.id, type: "STRING" },
    name: { value: record.name, type: "STRING" },
    abbreviation: { value: record.abbreviation, type: "STRING" },
    role: { value: record.role, type: "STRING" },
    accountKind: { value: record.accountKind, type: "STRING" },
    groupID: { value: record.groupID, type: "STRING" },
    createdAt: { value: record.createdAt, type: "TIMESTAMP" },
    webPasswordEncrypted: { value: record.webPasswordEncrypted || "", type: "STRING" },
  };
  await signAndPost(env, databasePath(env, "records/modify"), {
    operations: [{ operationType: "forceUpdate", record: { recordName: record.recordName, recordType: "User", fields } }],
  });
}

async function handlePutProfile(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  let name, abbreviation;
  try {
    const payload = await request.json();
    name = (payload.name || "").trim();
    abbreviation = (payload.abbreviation || "").trim();
    if (!name) throw new Error("Name fehlt");
  } catch {
    return jsonResponse(400, { error: "Name darf nicht leer sein." });
  }

  try {
    const record = await findUserRecordByUserID(env, session.gid, session.uid);
    if (!record) return jsonResponse(404, { error: "Nutzer nicht gefunden" });

    const canEditAbbreviation = isFullAdminSession(session);
    let nextAbbreviation = record.abbreviation;
    if (canEditAbbreviation && abbreviation && abbreviation.toLowerCase() !== record.abbreviation.toLowerCase()) {
      if (await isAbbreviationTakenInGroup(env, session.gid, abbreviation, session.uid)) {
        return jsonResponse(409, { error: "Dieses Kürzel ist schon vergeben." });
      }
      nextAbbreviation = abbreviation;
    }

    await saveUserRecord(env, { ...record, name, abbreviation: nextAbbreviation });

    const response = jsonResponse(200, { name, abbreviation: nextAbbreviation });
    return attachRefreshedSession(response, env, { ...session, name, abbr: nextAbbreviation });
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

/**
 * Pendant zu AdminCode.swift ("Admin", case-insensitive, kein Hash - siehe
 * dortiger Kommentar: bewusst einfach, kein echtes Sicherheitsmerkmal).
 * Jedes Mitglied darf das versuchen, kein Admin-Gate auf diesem Endpunkt -
 * genau das ist der Zweck (Selbst-Freischaltung ohne bestehenden Admin).
 */
async function handlePostAdminCode(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  let code;
  try {
    const payload = await request.json();
    code = (payload.code || "").trim();
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }
  if (!code || code.toLowerCase() !== "admin") {
    // 403, nicht 401 - 401 bedeutet in dieser App überall "Session ungültig",
    // ein falscher Code ist aber kein Auth-Problem, sonst würde das
    // Frontend fälschlich den Login-Screen zeigen statt eine Inline-Fehlermeldung.
    return jsonResponse(403, { error: "Falscher Code." });
  }

  try {
    const record = await findUserRecordByUserID(env, session.gid, session.uid);
    if (!record) return jsonResponse(404, { error: "Nutzer nicht gefunden" });
    await saveUserRecord(env, { ...record, role: "admin" });
    const response = jsonResponse(200, { role: "admin" });
    return attachRefreshedSession(response, env, { ...session, role: "admin" });
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function findAllEntriesForUser(env, groupID, userID) {
  // userID ist bei SurveyEntry NICHT Queryable (nur surveyDayID/groupID,
  // siehe README) - deshalb alle Einträge der Gruppe holen und hier filtern,
  // gleiches Muster wie findSurveyEntriesForDayIDs.
  const body = {
    query: {
      recordType: "SurveyEntry",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records
    .filter((r) => r.fields.userID && r.fields.userID.value === userID)
    .map((r) => ({ dayID: r.fields.surveyDayID.value }));
}

async function findAllSurveyDaysForGroup(env, groupID) {
  const body = {
    query: {
      recordType: "SurveyDay",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records.map((r) => ({ id: r.fields.dayID.value, date: berlinDateString(r.fields.date.value) }));
}

/** Montag-Sonntag, [start, end) - Pendant zu Calendar.dateInterval(of: .weekOfYear) mit Montag als Wochenstart. */
function weekIntervalContaining(dateString) {
  const [y, m, d] = dateString.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  const daysSinceMonday = (date.getUTCDay() + 6) % 7; // Mo->0 ... So->6
  const start = new Date(date);
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 7);
  const iso = (dt) => dt.toISOString().slice(0, 10);
  return { start: iso(start), end: iso(end) };
}

/** [start, end) für den Kalendermonat, in dem dateString liegt. */
function monthIntervalContaining(dateString) {
  const [y, m] = dateString.split("-").map(Number);
  const start = `${y}-${pad2(m)}-01`;
  const nextY = m === 12 ? y + 1 : y;
  const nextM = m === 12 ? 1 : m + 1;
  return { start, end: `${nextY}-${pad2(nextM)}-01` };
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

async function handleGetMembers(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  try {
    const users = await findUsersForGroup(env, session.gid);
    // Wie TeamMembersView.swift: Apotheken-Accounts tauchen hier nicht auf,
    // keine Sortierung (native App sortiert hier auch nicht).
    const members = users.filter((u) => u.accountKind === "labTeam");
    const response = jsonResponse(200, { members });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleGetMemberDetail(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  try {
    const record = await findUserRecordByUserID(env, session.gid, memberID);
    if (!record) return jsonResponse(404, { error: "Mitglied nicht gefunden" });

    const entries = await findAllEntriesForUser(env, session.gid, memberID);
    const payload = {
      id: record.id,
      name: record.name,
      abbreviation: record.abbreviation,
      role: record.role,
      totalTrips: entries.length,
      isFullAdminViewing: isFullAdminSession(session),
    };
    // Web-Zugang-Passwort nur für Haupt-Admins sichtbar, wie MemberDetailView.
    if (isFullAdminSession(session)) {
      payload.webPassword = record.webPasswordEncrypted ? await decryptWebPassword(env, record.webPasswordEncrypted) : "";
    }
    const response = jsonResponse(200, payload);
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleGetMemberStats(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  const url = new URL(request.url);
  const period = url.searchParams.get("period") === "month" ? "month" : "week";
  const dateParam = url.searchParams.get("date");
  const dateString = dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam) ? dateParam : berlinDateString(Date.now());

  try {
    const interval = period === "month" ? monthIntervalContaining(dateString) : weekIntervalContaining(dateString);
    const [entries, days] = await Promise.all([
      findAllEntriesForUser(env, session.gid, memberID),
      findAllSurveyDaysForGroup(env, session.gid),
    ]);
    const dateByDayID = Object.fromEntries(days.map((d) => [d.id, d.date]));
    const tripCount = entries.filter((e) => {
      const date = dateByDayID[e.dayID];
      return date && date >= interval.start && date < interval.end;
    }).length;
    const response = jsonResponse(200, { tripCount, periodStart: interval.start, periodEnd: interval.end });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePutMember(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isFullAdminSession(session)) return jsonResponse(403, { error: "Nur für Haupt-Admins" });

  let abbreviation;
  try {
    const payload = await request.json();
    abbreviation = (payload.abbreviation || "").trim();
    if (!abbreviation) throw new Error("Kürzel fehlt");
  } catch {
    return jsonResponse(400, { error: "Kürzel darf nicht leer sein." });
  }

  try {
    const record = await findUserRecordByUserID(env, session.gid, memberID);
    if (!record) return jsonResponse(404, { error: "Mitglied nicht gefunden" });

    if (abbreviation.toLowerCase() !== record.abbreviation.toLowerCase()) {
      if (await isAbbreviationTakenInGroup(env, session.gid, abbreviation, memberID)) {
        return jsonResponse(409, { error: "Dieses Kürzel ist schon vergeben." });
      }
    }
    await saveUserRecord(env, { ...record, abbreviation });
    const response = jsonResponse(200, { abbreviation });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePutMemberWebPassword(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isFullAdminSession(session)) return jsonResponse(403, { error: "Nur für Haupt-Admins" });

  let password;
  try {
    const payload = await request.json();
    password = (payload.password || "").trim();
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    const record = await findUserRecordByUserID(env, session.gid, memberID);
    if (!record) return jsonResponse(404, { error: "Mitglied nicht gefunden" });

    let encrypted = null;
    if (password) {
      encrypted = await encryptWebPassword(env, password);
      const existing = await findUserByEncryptedPassword(env, encrypted);
      if (existing && existing.id !== memberID) {
        return jsonResponse(409, { error: "Dieses Passwort ist schon einem anderen Mitglied zugewiesen." });
      }
    }
    await saveUserRecord(env, { ...record, webPasswordEncrypted: encrypted });
    const response = jsonResponse(200, { ok: true });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePutMemberRole(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isFullAdminSession(session)) return jsonResponse(403, { error: "Nur für Haupt-Admins" });
  if (memberID === session.uid) return jsonResponse(403, { error: "Eigene Rolle kann nicht geändert werden." });

  let role;
  try {
    const payload = await request.json();
    role = payload.role;
    if (role !== "member" && role !== "viceAdmin") throw new Error("invalid role");
  } catch {
    return jsonResponse(400, { error: "Ungültige Rolle" });
  }

  try {
    const record = await findUserRecordByUserID(env, session.gid, memberID);
    if (!record) return jsonResponse(404, { error: "Mitglied nicht gefunden" });
    // Haupt-Admin-Ernennung/-Entzug bleibt bewusst App-only (dort auch nur
    // über den Entwicklermodus möglich) - hier nicht nachgebildet.
    if (record.role === "admin") return jsonResponse(403, { error: "Haupt-Admin-Rolle kann hier nicht geändert werden." });

    await saveUserRecord(env, { ...record, role });
    const response = jsonResponse(200, { role });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleDeleteMember(request, env, memberID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isFullAdminSession(session)) return jsonResponse(403, { error: "Nur für Haupt-Admins" });
  if (memberID === session.uid) return jsonResponse(403, { error: "Eigenes Konto kann nicht entfernt werden." });

  try {
    const record = await findUserRecordByUserID(env, session.gid, memberID);
    if (!record) return jsonResponse(404, { error: "Mitglied nicht gefunden" });

    if (record.role === "admin") {
      const users = await findUsersForGroup(env, session.gid);
      const adminCount = users.filter((u) => u.role === "admin").length;
      if (adminCount <= 1) return jsonResponse(409, { error: "Das letzte Admin-Konto der Gruppe kann nicht entfernt werden." });
    }

    await signAndPost(env, databasePath(env, "records/modify"), {
      operations: [{ operationType: "forceDelete", record: { recordName: record.recordName } }],
    });
    const response = jsonResponse(200, { ok: true });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleGetSurveyDays(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  const url = new URL(request.url);
  const from = url.searchParams.get("from") || "";
  const to = url.searchParams.get("to") || "";
  const mode = url.searchParams.get("mode") === "signup" ? "signup" : "browse";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || from > to) {
    return jsonResponse(400, { error: "Ungültiger Zeitraum (from/to als YYYY-MM-DD, from <= to erwartet)" });
  }

  try {
    let days = await findSurveyDaysInRange(env, session.gid, from, to);
    // "signup"-Modus legt fehlende Mo-Do-Tage an (ensureDaysExist-Äquivalent)
    // - "browse" ist bewusst reiner Lesezugriff, sonst würde bloßes
    // Kalender-Blättern in weit entfernte Monate leere Tage anlegen.
    if (mode === "signup") {
      await ensureSurveyDaysExist(env, session.gid, from, to, days);
      days = await findSurveyDaysInRange(env, session.gid, from, to);
    }
    const [entries, users] = await Promise.all([
      findSurveyEntriesForDayIDs(env, session.gid, days.map((d) => d.id)),
      findUsersForGroup(env, session.gid),
    ]);
    const userByID = Object.fromEntries(users.map((u) => [u.id, u]));
    const enrichedEntries = entries.map((entry) => ({
      ...entry,
      name: userByID[entry.userID] ? userByID[entry.userID].name : "",
      abbreviation: userByID[entry.userID] ? userByID[entry.userID].abbreviation : "",
    }));
    const response = jsonResponse(200, { days, entries: enrichedEntries, members: users });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

// MARK: - Proben-Status (team-weite, rein lesende Ansicht - siehe
// CloudKitSamplesRepository.swift; kein Schreibpfad hier, das lab-team-
// seitige SamplesListView ruft nie setHasSamples auf)

async function findLocationsForGroup(env, groupID) {
  const body = {
    query: {
      recordType: "SampleLocation",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records.map((r) => ({
    id: r.fields.locationID.value,
    name: r.fields.name.value,
    address: r.fields.address ? r.fields.address.value : "",
    usesQRCheckIn: r.fields.usesQRCheckIn ? r.fields.usesQRCheckIn.value !== 0 : true,
  }));
}

async function findSampleReportsForDay(env, groupID, dayMs) {
  const body = {
    query: {
      recordType: "SampleReport",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
        { fieldName: "day", comparator: "EQUALS", fieldValue: { value: dayMs, type: "TIMESTAMP" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records.map((r) => ({
    locationID: r.fields.locationID.value,
    hasSamples: r.fields.hasSamples.value === 1,
    statusNote: r.fields.statusNote ? r.fields.statusNote.value : "",
  }));
}

async function handleGetSamples(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  const url = new URL(request.url);
  const dateParam = url.searchParams.get("date");
  const dateString = dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam) ? dateParam : berlinDateString(Date.now());

  try {
    const dayMs = berlinMidnightMs(dateString);
    const [locations, reports] = await Promise.all([
      findLocationsForGroup(env, session.gid),
      findSampleReportsForDay(env, session.gid, dayMs),
    ]);
    const locationByID = Object.fromEntries(locations.map((l) => [l.id, l]));
    // Wie SamplesListView: nur Standorte MIT Meldung an diesem Tag tauchen
    // auf - an ruhigen Tagen ist die Liste einfach leer, kein "keine
    // Meldung" für jede Apotheke.
    const items = reports
      .map((report) => {
        const location = locationByID[report.locationID];
        if (!location) return null;
        return {
          locationID: report.locationID,
          name: location.name,
          address: location.address,
          hasSamples: report.hasSamples,
          statusNote: report.statusNote,
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name, "de"));

    const response = jsonResponse(200, { date: dateString, items });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

// MARK: - Apotheken verwalten (SampleLocation-CRUD + manuelles Melden,
// siehe PharmacyManagementView.swift/PharmacyDetailView) - admin-only,
// paralleler Weg zum tokenbasierten /api/report auf dem Apotheken-Worker.

function reportRecordName(locationId, dateString) {
  return `report-${locationId}-${dateString}`;
}

async function findLocationRecordByID(env, groupID, locationID) {
  const body = {
    query: {
      recordType: "SampleLocation",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
        { fieldName: "locationID", comparator: "EQUALS", fieldValue: { value: locationID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  if (!records.length) return null;
  const record = records[0];
  return {
    recordName: record.recordName,
    id: record.fields.locationID.value,
    groupID: record.fields.groupID ? record.fields.groupID.value : null,
    name: record.fields.name.value,
    address: record.fields.address ? record.fields.address.value : "",
    ownerUserID: record.fields.ownerUserID ? record.fields.ownerUserID.value : null,
    token: record.fields.token ? record.fields.token.value : "",
    usesQRCheckIn: record.fields.usesQRCheckIn ? record.fields.usesQRCheckIn.value !== 0 : true,
  };
}

async function getSampleReport(env, recordName) {
  const result = await signAndPost(env, databasePath(env, "records/lookup"), { records: [{ recordName }] });
  const records = result.records || [];
  if (!records.length || !records[0].fields) return null;
  return { hasSamples: records[0].fields.hasSamples.value === 1 };
}

async function saveSampleReport(env, recordName, groupID, locationID, hasSamples, dayMs, exists) {
  const fields = {
    reportID: { value: crypto.randomUUID(), type: "STRING" },
    locationID: { value: locationID, type: "STRING" },
    day: { value: dayMs, type: "TIMESTAMP" },
    hasSamples: { value: hasSamples ? 1 : 0, type: "INT64" },
    statusNote: { value: "", type: "STRING" },
    reportedAt: { value: Date.now(), type: "TIMESTAMP" },
  };
  if (groupID) fields.groupID = { value: groupID, type: "STRING" };
  await signAndPost(env, databasePath(env, "records/modify"), {
    operations: [{ operationType: exists ? "forceUpdate" : "create", record: { recordName, recordType: "SampleReport", fields } }],
  });
}

async function handleGetPharmacies(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  try {
    const today = berlinDateString(Date.now());
    const dayMs = berlinMidnightMs(today);
    const [locations, reports] = await Promise.all([
      findLocationsForGroup(env, session.gid),
      findSampleReportsForDay(env, session.gid, dayMs),
    ]);
    const reportByLocation = Object.fromEntries(reports.map((r) => [r.locationID, r]));
    const pharmacies = locations
      .map((l) => ({
        id: l.id,
        name: l.name,
        address: l.address,
        usesQRCheckIn: l.usesQRCheckIn,
        hasSamples: reportByLocation[l.id] ? reportByLocation[l.id].hasSamples : null,
      }))
      .sort((a, b) => a.name.localeCompare(b.name, "de"));
    const response = jsonResponse(200, { pharmacies });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleGetPharmacyDetail(request, env, pharmacyID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  try {
    const location = await findLocationRecordByID(env, session.gid, pharmacyID);
    if (!location) return jsonResponse(404, { error: "Apotheke nicht gefunden" });

    const today = berlinDateString(Date.now());
    const report = await getSampleReport(env, reportRecordName(location.id, today));

    const response = jsonResponse(200, {
      id: location.id,
      name: location.name,
      address: location.address,
      usesQRCheckIn: location.usesQRCheckIn,
      checkInURL: `https://mediproben.com?token=${location.token}`,
      hasSamples: report ? report.hasSamples : null,
    });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostPharmacy(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  let name, address, usesQRCheckIn;
  try {
    const payload = await request.json();
    name = (payload.name || "").trim();
    address = (payload.address || "").trim();
    usesQRCheckIn = payload.usesQRCheckIn !== false;
    if (!name) throw new Error("Name fehlt");
  } catch {
    return jsonResponse(400, { error: "Name darf nicht leer sein." });
  }

  try {
    const locationID = crypto.randomUUID();
    const recordName = `location-${locationID}`;
    const fields = {
      locationID: { value: locationID, type: "STRING" },
      groupID: { value: session.gid, type: "STRING" },
      name: { value: name, type: "STRING" },
      address: { value: address, type: "STRING" },
      token: { value: crypto.randomUUID(), type: "STRING" },
      usesQRCheckIn: { value: usesQRCheckIn ? 1 : 0, type: "INT64" },
    };
    await signAndPost(env, databasePath(env, "records/modify"), {
      operations: [{ operationType: "create", record: { recordName, recordType: "SampleLocation", fields } }],
    });
    const response = jsonResponse(200, { id: locationID, name, address, usesQRCheckIn });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostPharmacyReport(request, env, pharmacyID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  let hasSamples;
  try {
    const payload = await request.json();
    hasSamples = Boolean(payload.hasSamples);
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    const location = await findLocationRecordByID(env, session.gid, pharmacyID);
    if (!location) return jsonResponse(404, { error: "Apotheke nicht gefunden" });

    const today = berlinDateString(Date.now());
    const dayMs = berlinMidnightMs(today);
    const recordName = reportRecordName(location.id, today);
    const existing = await getSampleReport(env, recordName);
    await saveSampleReport(env, recordName, session.gid, location.id, hasSamples, dayMs, existing !== null);

    const response = jsonResponse(200, { ok: true, hasSamples });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleDeletePharmacy(request, env, pharmacyID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  try {
    const location = await findLocationRecordByID(env, session.gid, pharmacyID);
    if (!location) return jsonResponse(404, { error: "Apotheke nicht gefunden" });

    await signAndPost(env, databasePath(env, "records/modify"), {
      operations: [{ operationType: "forceDelete", record: { recordName: location.recordName } }],
    });
    const response = jsonResponse(200, { ok: true });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

// MARK: - Admin-PDF-Auswertungen (JS-Port von MonthlyReportGenerator.swift /
// SamplesReportGenerator.swift - beide dort pure Aggregationsfunktionen,
// hier 1:1 nachgebaut; das PDF selbst baut das Frontend, siehe
// buildSimplePdfBytes in public/index.html)

function monthRangeDateStrings(year, month) {
  const pad2 = (n) => String(n).padStart(2, "0");
  const from = `${year}-${pad2(month)}-01`;
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const to = `${year}-${pad2(month)}-${pad2(lastDay)}`;
  return { from, to };
}

function parseMonthYear(url) {
  const month = parseInt(url.searchParams.get("month"), 10);
  const year = parseInt(url.searchParams.get("year"), 10);
  if (!Number.isInteger(month) || month < 1 || month > 12 || !Number.isInteger(year)) return null;
  return { month, year };
}

async function findSampleReportsInRange(env, groupID, fromDateString, toDateString) {
  const PAD_MS = 6 * 60 * 60 * 1000;
  const fromMs = Date.parse(`${fromDateString}T00:00:00Z`) - PAD_MS;
  const toMs = Date.parse(`${toDateString}T00:00:00Z`) + 24 * 60 * 60 * 1000 + PAD_MS;
  const body = {
    query: {
      recordType: "SampleReport",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
        { fieldName: "day", comparator: "GREATER_THAN_OR_EQUALS", fieldValue: { value: fromMs, type: "TIMESTAMP" } },
        { fieldName: "day", comparator: "LESS_THAN_OR_EQUALS", fieldValue: { value: toMs, type: "TIMESTAMP" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  return records
    .map((r) => ({
      locationID: r.fields.locationID.value,
      day: berlinDateString(r.fields.day.value),
      hasSamples: r.fields.hasSamples.value === 1,
    }))
    .filter((r) => r.day >= fromDateString && r.day <= toDateString);
}

async function handleGetMonthlyReport(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  const url = new URL(request.url);
  const monthYear = parseMonthYear(url);
  if (!monthYear) return jsonResponse(400, { error: "Ungültiger Monat/Jahr" });

  try {
    const { from, to } = monthRangeDateStrings(monthYear.year, monthYear.month);
    const days = await findSurveyDaysInRange(env, session.gid, from, to);
    const [entries, users] = await Promise.all([
      findSurveyEntriesForDayIDs(env, session.gid, days.map((d) => d.id)),
      findUsersForGroup(env, session.gid),
    ]);
    const userByID = Object.fromEntries(users.map((u) => [u.id, u]));

    const counts = {};
    for (const entry of entries) counts[entry.userID] = (counts[entry.userID] || 0) + 1;
    const lines = Object.entries(counts)
      .filter(([userID]) => userByID[userID])
      .map(([userID, tripCount]) => ({ userName: userByID[userID].name, tripCount }))
      .sort((a, b) => b.tripCount - a.tripCount || a.userName.localeCompare(b.userName, "de"));

    const response = jsonResponse(200, { lines });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleGetSamplesReport(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  const url = new URL(request.url);
  const monthYear = parseMonthYear(url);
  if (!monthYear) return jsonResponse(400, { error: "Ungültiger Monat/Jahr" });

  try {
    const { from, to } = monthRangeDateStrings(monthYear.year, monthYear.month);
    const [reports, locations] = await Promise.all([
      findSampleReportsInRange(env, session.gid, from, to),
      findLocationsForGroup(env, session.gid),
    ]);
    const locationByID = Object.fromEntries(locations.map((l) => [l.id, l]));

    const counts = {};
    for (const report of reports) {
      if (!report.hasSamples) continue;
      counts[report.locationID] = (counts[report.locationID] || 0) + 1;
    }
    const lines = Object.entries(counts)
      .filter(([locationID]) => locationByID[locationID])
      .map(([locationID, daysWithSamples]) => ({ locationName: locationByID[locationID].name, daysWithSamples }))
      .sort((a, b) => b.daysWithSamples - a.daysWithSamples || a.locationName.localeCompare(b.locationName, "de"));

    const response = jsonResponse(200, { lines });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

// MARK: - Schreibende Umfragen-Endpunkte (Ein-/Austragen, Sperren) - erste
// echte serverseitige Autorisierungslogik im ganzen Projekt: die
// Vergangenheits-Regel (canEditSurveyDay in EffectiveAdmin.swift) ist bisher
// überall nur Client-UI-Gate (BACKLOG #2), hier wird sie erstmals wirklich
// durchgesetzt, weil ein öffentlicher HTTP-Endpunkt ein größeres Ziel ist
// als eine kompilierte App.

async function findSurveyDayByID(env, groupID, dayID) {
  const body = {
    query: {
      recordType: "SurveyDay",
      filterBy: [
        { fieldName: "groupID", comparator: "EQUALS", fieldValue: { value: groupID, type: "STRING" } },
        { fieldName: "dayID", comparator: "EQUALS", fieldValue: { value: dayID, type: "STRING" } },
      ],
    },
  };
  const records = await queryAllRecords(env, body);
  if (!records.length) return null;
  const r = records[0];
  return {
    recordName: r.recordName,
    id: r.fields.dayID.value,
    groupID: r.fields.groupID ? r.fields.groupID.value : null,
    dateMs: r.fields.date.value,
    date: berlinDateString(r.fields.date.value),
    isLocked: r.fields.isLocked ? r.fields.isLocked.value === 1 : false,
    lockReason: r.fields.lockReason ? r.fields.lockReason.value : null,
  };
}

async function recordExists(env, recordName) {
  const result = await signAndPost(env, databasePath(env, "records/lookup"), { records: [{ recordName }] });
  const records = result.records || [];
  return records.length > 0 && !!records[0].fields;
}

/** Admins dürfen jeden Tag bearbeiten, alle anderen nur heute/zukünftig - Pendant zu canEditSurveyDay in EffectiveAdmin.swift. */
function canEditDay(session, dayDateString) {
  if (isAdminSession(session)) return true;
  return dayDateString >= berlinDateString(Date.now());
}

function parseTargetUserID(payload, session) {
  return payload.userID && typeof payload.userID === "string" ? payload.userID : session.uid;
}

async function handlePostSurveyEntry(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  let dayID, targetUserID;
  try {
    const payload = await request.json();
    dayID = payload.dayID;
    if (!dayID || typeof dayID !== "string") throw new Error("dayID fehlt");
    targetUserID = parseTargetUserID(payload, session);
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  if (targetUserID !== session.uid && !isAdminSession(session)) {
    return jsonResponse(403, { error: "Nur Admins können für andere Mitglieder eintragen" });
  }

  try {
    const day = await findSurveyDayByID(env, session.gid, dayID);
    if (!day) return jsonResponse(404, { error: "Unbekannter Tag" });
    if (day.isLocked) return jsonResponse(409, { error: "Dieser Tag ist gesperrt" });
    if (!canEditDay(session, day.date)) {
      return jsonResponse(403, { error: "Vergangene Tage können nur von Admins bearbeitet werden" });
    }

    const recordName = `entry-${dayID}-${targetUserID}`;
    // Deterministische ID wie im App-Pendant (signIn) - schon eingetragen
    // ist ein No-Op, kein Fehler (idempotent, kein Doppel-Eintrag möglich).
    if (!(await recordExists(env, recordName))) {
      const record = {
        recordName,
        recordType: "SurveyEntry",
        fields: {
          entryID: { value: crypto.randomUUID(), type: "STRING" },
          surveyDayID: { value: dayID, type: "STRING" },
          userID: { value: targetUserID, type: "STRING" },
          groupID: { value: session.gid, type: "STRING" },
          createdAt: { value: Date.now(), type: "TIMESTAMP" },
        },
      };
      await signAndPost(env, databasePath(env, "records/modify"), {
        operations: [{ operationType: "create", record }],
      });
    }
    const response = jsonResponse(200, { ok: true });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handleDeleteSurveyEntry(request, env) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });

  let dayID, targetUserID;
  try {
    const payload = await request.json();
    dayID = payload.dayID;
    if (!dayID || typeof dayID !== "string") throw new Error("dayID fehlt");
    targetUserID = parseTargetUserID(payload, session);
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  if (targetUserID !== session.uid && !isAdminSession(session)) {
    return jsonResponse(403, { error: "Nur Admins können für andere Mitglieder austragen" });
  }

  try {
    // Anders als bei signIn prüft das App-Pendant (signOut) weder Sperre
    // noch Tag-Existenz - Austragen darf nie an einer Sperre scheitern,
    // sonst käme man aus einem Fehlzustand nicht mehr raus. Die
    // Vergangenheits-Regel gilt trotzdem, sonst könnte man rückwirkend
    // Fahrten verschwinden lassen.
    const day = await findSurveyDayByID(env, session.gid, dayID);
    if (day && !canEditDay(session, day.date)) {
      return jsonResponse(403, { error: "Vergangene Tage können nur von Admins bearbeitet werden" });
    }
    try {
      await signAndPost(env, databasePath(env, "records/modify"), {
        operations: [{ operationType: "forceDelete", record: { recordName: `entry-${dayID}-${targetUserID}` } }],
      });
    } catch {
      // best-effort wie im App-Pendant - "schon nicht mehr da" ist kein Fehler
    }
    const response = jsonResponse(200, { ok: true });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

async function handlePostSurveyDayLock(request, env, dayID) {
  const session = await verifySession(request, env);
  if (!session) return jsonResponse(401, { error: "Nicht angemeldet" });
  if (!isAdminSession(session)) return jsonResponse(403, { error: "Nur für Admins" });

  let locked, reason;
  try {
    const payload = await request.json();
    locked = Boolean(payload.locked);
    reason = typeof payload.reason === "string" ? payload.reason.trim() : "";
  } catch {
    return jsonResponse(400, { error: "Ungültige Anfrage" });
  }

  try {
    const day = await findSurveyDayByID(env, session.gid, dayID);
    if (!day) return jsonResponse(404, { error: "Unbekannter Tag" });

    // Volles Feld-Set statt nur der geänderten Felder - unklar/ungetestet,
    // ob CloudKit Web Services' forceUpdate fehlende Felder unverändert
    // lässt oder löscht, deshalb hier auf Nummer sicher.
    const record = {
      recordName: day.recordName,
      recordType: "SurveyDay",
      fields: {
        dayID: { value: day.id, type: "STRING" },
        groupID: { value: day.groupID, type: "STRING" },
        date: { value: day.dateMs, type: "TIMESTAMP" },
        isLocked: { value: locked ? 1 : 0, type: "INT64" },
        lockReason: { value: locked ? reason : "", type: "STRING" },
      },
    };
    await signAndPost(env, databasePath(env, "records/modify"), {
      operations: [{ operationType: "forceUpdate", record }],
    });
    const response = jsonResponse(200, { ok: true, locked, lockReason: locked ? reason : null });
    return attachRefreshedSession(response, env, session);
  } catch (error) {
    return jsonResponse(502, { error: String(error), detail: error.detail });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/api/login") {
      return handlePostLogin(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/logout") {
      return handlePostLogout();
    }
    if (request.method === "GET" && url.pathname === "/api/me") {
      return handleGetMe(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/survey-days") {
      return handleGetSurveyDays(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/samples") {
      return handleGetSamples(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/reports/monthly") {
      return handleGetMonthlyReport(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/reports/samples") {
      return handleGetSamplesReport(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/survey-entries") {
      return handlePostSurveyEntry(request, env);
    }
    if (request.method === "DELETE" && url.pathname === "/api/survey-entries") {
      return handleDeleteSurveyEntry(request, env);
    }
    const lockMatch = url.pathname.match(/^\/api\/survey-days\/([^/]+)\/lock$/);
    if (request.method === "POST" && lockMatch) {
      return handlePostSurveyDayLock(request, env, decodeURIComponent(lockMatch[1]));
    }
    if (request.method === "PUT" && url.pathname === "/api/profile") {
      return handlePutProfile(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/profile/admin-code") {
      return handlePostAdminCode(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/members") {
      return handleGetMembers(request, env);
    }
    const memberStatsMatch = url.pathname.match(/^\/api\/members\/([^/]+)\/stats$/);
    if (request.method === "GET" && memberStatsMatch) {
      return handleGetMemberStats(request, env, decodeURIComponent(memberStatsMatch[1]));
    }
    const memberPasswordMatch = url.pathname.match(/^\/api\/members\/([^/]+)\/web-password$/);
    if (request.method === "PUT" && memberPasswordMatch) {
      return handlePutMemberWebPassword(request, env, decodeURIComponent(memberPasswordMatch[1]));
    }
    const memberRoleMatch = url.pathname.match(/^\/api\/members\/([^/]+)\/role$/);
    if (request.method === "PUT" && memberRoleMatch) {
      return handlePutMemberRole(request, env, decodeURIComponent(memberRoleMatch[1]));
    }
    const memberMatch = url.pathname.match(/^\/api\/members\/([^/]+)$/);
    if (request.method === "GET" && memberMatch) {
      return handleGetMemberDetail(request, env, decodeURIComponent(memberMatch[1]));
    }
    if (request.method === "PUT" && memberMatch) {
      return handlePutMember(request, env, decodeURIComponent(memberMatch[1]));
    }
    if (request.method === "DELETE" && memberMatch) {
      return handleDeleteMember(request, env, decodeURIComponent(memberMatch[1]));
    }
    if (request.method === "GET" && url.pathname === "/api/pharmacies") {
      return handleGetPharmacies(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/pharmacies") {
      return handlePostPharmacy(request, env);
    }
    const pharmacyReportMatch = url.pathname.match(/^\/api\/pharmacies\/([^/]+)\/report$/);
    if (request.method === "POST" && pharmacyReportMatch) {
      return handlePostPharmacyReport(request, env, decodeURIComponent(pharmacyReportMatch[1]));
    }
    const pharmacyMatch = url.pathname.match(/^\/api\/pharmacies\/([^/]+)$/);
    if (request.method === "GET" && pharmacyMatch) {
      return handleGetPharmacyDetail(request, env, decodeURIComponent(pharmacyMatch[1]));
    }
    if (request.method === "DELETE" && pharmacyMatch) {
      return handleDeletePharmacy(request, env, decodeURIComponent(pharmacyMatch[1]));
    }
    // Alles andere (/, /index.html, ...) wird schon automatisch von den
    // Workers Static Assets aus public/ ausgeliefert, bevor dieser Fetch-
    // Handler überhaupt läuft - dieser Fall greift nur für unbekannte Pfade.
    return new Response("Not found", { status: 404 });
  },
};
