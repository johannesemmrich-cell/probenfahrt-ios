/**
 * Cloudflare-Worker für den Apotheken-Web-Check-in unter mediproben.com.
 * Nur per QR-Code-Token erreichbar (siehe public/index.html) - kein
 * Passwort-Login mehr hier, das lebt komplett getrennt in web/worker-app/
 * (app.mediproben.com). Gemeinsame CloudKit-Signatur-Logik liegt in
 * web/shared/cloudkit.js (siehe dort für die DER-Signatur-Begründung).
 */

import { databasePath, signAndPost } from "../../shared/cloudkit.js";

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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/api/pharmacy") {
      return handleGetPharmacy(request, env);
    }
    if (request.method === "POST" && url.pathname === "/api/report") {
      return handlePostReport(request, env);
    }
    // Alles andere (/, /index.html, ...) wird schon automatisch von den
    // Workers Static Assets aus public/ ausgeliefert, bevor dieser Fetch-
    // Handler überhaupt läuft - dieser Fall greift nur für unbekannte Pfade.
    return new Response("Not found", { status: 404 });
  },
};
