// El tracto va ligado al conductor: al desasignar o terminar la ruta no debe
// quedar ninguna fila/tarjeta que muestre solo la patente del tracto.
// Extrae funciones reales de js/*.js y las ejecuta en un vm con DOM mínimo.
// Datos ficticios. Uso: node --test tests/frontend/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function extract(src, name) {
  const i = src.indexOf(`function ${name}(`);
  assert.ok(i >= 0, `no existe ${name}`);
  let depth = 0, j = src.indexOf("{", i);
  for (let k = j; k < src.length; k++) {
    if (src[k] === "{") depth++;
    else if (src[k] === "}" && --depth === 0) return src.slice(i, k + 1);
  }
  throw new Error("llaves desbalanceadas");
}
const escapeHTML = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const ORG_A = "0000000a-0000-0000-0000-000000000000";
const ORG_B = "0000000b-0000-0000-0000-000000000000";
// --- FINALIZADOS (js/conductores.js): funciones reales en un vm ---
function loadCompletedSandbox({ activeOrganizationId, conductors, trips }) {
  const src = fs.readFileSync("js/conductores.js", "utf8");
  const code = ["getOrganizationConductorsById", "getCompletedTripsForActiveOrganization",
    "renderCompletedPools", "returnCompletedTripToAvailable"].map((n) => extract(src, n)).join("\n");
  const sb = {
    completedPool: { innerHTML: "" }, escapeHTML, activeOrganizationId,
    currentConductors: conductors, currentTrips: trips,
    returnedCompletedTripIds: new Set(), saved: 0,
    saveReturnedCompletedTripIds() { sb.saved++; },
  };
  vm.createContext(sb);
  vm.runInContext(code, sb);
  return sb;
}
// Conductores de org A (lo que devuelve organization_drivers filtrado por org A).
const CONDUCTORES_A = [
  { id: "c-a1", driver_id: "FO-A1", nombre: "Conductor Ficticio A1", tracto: { id: "tr-a1", patente: "TRAA11" } },
  { id: "c-a2", driver_id: "FO-A2", nombre: "Conductor Ficticio A2", tracto: { id: "tr-a2", patente: "TRAA22" } },
];
const TRIPS = [
  { id: "t-a1", conductor_id: "c-a1", conductor: "Conductor Ficticio A1", patente: "TRAA11", empresa_id: ORG_A, ruta: "Ruta A", fecha_finalizacion: "2026-10-30T10:00:00Z" },
  { id: "t-a2", conductor_id: "c-a2", conductor: "Conductor Ficticio A2", patente: "TRAA22", empresa_id: ORG_A, ruta: null, fecha_finalizacion: "2026-10-30T11:00:00Z" },
  { id: "t-a3", conductor_id: null, conductor: null, patente: "TRAA99", empresa_id: ORG_A, ruta: "Ruta A", fecha_finalizacion: "2026-10-30T12:00:00Z" },
  { id: "t-b1", conductor_id: "c-b1", conductor: "Conductor Ficticio B1", patente: "TRBB11", empresa_id: ORG_B, ruta: null, fecha_finalizacion: "2026-10-30T10:00:00Z" },
];
const SNAP = process.env.SNAP_DIR || "/tmp";

test("FINALIZADOS: una fila por viaje con conductor y tracto juntos", () => {
  const sb = loadCompletedSandbox({ activeOrganizationId: ORG_A, conductors: CONDUCTORES_A, trips: TRIPS });
  vm.runInContext("renderCompletedPools(currentTrips)", sb);
  const html = sb.completedPool.innerHTML;
  fs.mkdirSync(SNAP, { recursive: true });
  fs.writeFileSync(`${SNAP}/completed_pool.html`, html);
  const rows = html.split("<article").slice(1);
  assert.equal(rows.length, 2, "debe haber 2 filas (t-a1, t-a2)");
  for (const [id, nombre, pat] of [["t-a1", "Conductor Ficticio A1", "TRAA11"], ["t-a2", "Conductor Ficticio A2", "TRAA22"]]) {
    const row = rows.find((r) => r.includes(`data-trip-id="${id}"`));
    assert.ok(row, `falta la fila ${id}`);
    assert.ok(row.includes(nombre) && row.includes(pat), `la fila ${id} no tiene conductor y tracto juntos`);
  }
});

test("FINALIZADOS: un viaje sin conductor no genera fila (ni tracto suelto)", () => {
  const sb = loadCompletedSandbox({ activeOrganizationId: ORG_A, conductors: CONDUCTORES_A, trips: TRIPS });
  vm.runInContext("renderCompletedPools(currentTrips)", sb);
  assert.ok(!sb.completedPool.innerHTML.includes("t-a3"));
  assert.ok(!sb.completedPool.innerHTML.includes("TRAA99"));
  assert.ok(!sb.completedPool.innerHTML.includes("SIN CONDUCTOR"));
});

test("DEVOLVER A DISPONIBLES: usa el id correcto y saca la fila de la vista", () => {
  const sb = loadCompletedSandbox({ activeOrganizationId: ORG_A, conductors: CONDUCTORES_A, trips: TRIPS });
  vm.runInContext("renderCompletedPools(currentTrips)", sb);
  const m = sb.completedPool.innerHTML.match(/return-available-button" data-trip-id="([^"]+)"/);
  assert.ok(m, "no hay botón DEVOLVER A DISPONIBLES");
  assert.equal(m[1], "t-a2");
  sb.tid = m[1];
  assert.equal(vm.runInContext("returnCompletedTripToAvailable(tid)", sb), true);
  assert.ok(sb.returnedCompletedTripIds.has("t-a2") && sb.returnedCompletedTripIds.size === 1);
  assert.equal(sb.saved, 1, "no persistió");
  assert.ok(!sb.completedPool.innerHTML.includes('data-trip-id="t-a2"'), "la fila sigue en la vista");
  assert.ok(sb.completedPool.innerHTML.includes('data-trip-id="t-a1"'), "se borró otra fila");
});

test("aislamiento: org A no ve conductores/tractos/viajes de org B ni vía el botón", () => {
  const sb = loadCompletedSandbox({ activeOrganizationId: ORG_A, conductors: CONDUCTORES_A, trips: TRIPS });
  vm.runInContext("renderCompletedPools(currentTrips)", sb);
  const html = sb.completedPool.innerHTML;
  for (const x of ["t-b1", "TRBB11", "Conductor Ficticio B1", "c-b1"]) assert.ok(!html.includes(x), `org A ve ${x}`);
  sb.tid = "t-b1"; // data-trip-id manipulado con un viaje de B
  assert.equal(vm.runInContext("returnCompletedTripToAvailable(tid)", sb), false);
  assert.equal(sb.returnedCompletedTripIds.size, 0);
  assert.equal(sb.saved, 0);
  // y org B (con sus conductores) ve solo lo suyo
  const sbB = loadCompletedSandbox({ activeOrganizationId: ORG_B,
    conductors: [{ id: "c-b1", driver_id: "FO-B1", nombre: "Conductor Ficticio B1", tracto: { patente: "TRBB11" } }], trips: TRIPS });
  vm.runInContext("renderCompletedPools(currentTrips)", sbB);
  assert.ok(sbB.completedPool.innerHTML.includes("TRBB11") && sbB.completedPool.innerHTML.includes("Conductor Ficticio B1"));
  for (const x of ["TRAA11", "TRAA22", "t-a1", "t-a2", "Conductor Ficticio A"]) assert.ok(!sbB.completedPool.innerHTML.includes(x), `org B ve ${x}`);
  sbB.tid = "t-a2";
  assert.equal(vm.runInContext("returnCompletedTripToAvailable(tid)", sbB), false);
});

test("dashboard: un viaje abierto sin conductor (desasignado) no genera tarjeta solo-tracto", () => {
  const src = fs.readFileSync("js/dashboard.js", "utf8");
  const sandbox = {
    normalizePlate: (v) => String(v || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase(),
    buildEventTimeline: () => [],
    out: null,
    open: [
      { id: "v1", patente: "TRAA22", conductor_id: null, conductor: null, empresa_id: ORG_A, ruta: "Ruta A", fecha_finalizacion: null, created_at: "2026-10-30T09:00:00Z" },
      { id: "v2", patente: "TRAA33", conductor_id: "c-a2", conductor: "Conductor Ficticio A2", empresa_id: ORG_A, ruta: "Ruta A", fecha_finalizacion: null, created_at: "2026-10-30T09:00:00Z" },
    ],
  };
  vm.runInNewContext(extract(src, "buildUnits") + "; out = buildUnits(open, [], { 'c-a2': { nombre: 'Conductor Ficticio A2', driver_id: 'FO-A2' } });", sandbox);
  fs.writeFileSync(`${process.env.SNAP_DIR || "/tmp"}/dashboard_units.json`, JSON.stringify(sandbox.out, null, 2));
  assert.equal(JSON.stringify(sandbox.out.map((u) => u.patente)), JSON.stringify(["TRAA33"]), "queda una tarjeta solo con el tracto");
  assert.ok(sandbox.out.every((u) => u.conductor_id), "unidad sin conductor");
});

test("dashboard legacy: un reporte sin conductor no genera tarjeta solo-tracto", () => {
  const src = fs.readFileSync("js/dashboard.js", "utf8");
  const sandbox = {
    normalizePlate: (v) => String(v || "").replace(/[^a-zA-Z0-9]/g, "").toUpperCase(),
    out: null,
    reports: [
      { viaje_id: null, patente: "TRAA44", conductor_id: null, conductor: null, estado: "En ruta", timestamp: "2026-10-30T09:00:00Z" },
      { viaje_id: null, patente: "TRAA55", conductor_id: null, conductor: "Conductor Ficticio Legacy", estado: "En ruta", timestamp: "2026-10-30T09:00:00Z" },
    ],
  };
  vm.runInNewContext(extract(src, "buildLegacyUnits") + "; out = buildLegacyUnits(reports, {});", sandbox);
  assert.equal(JSON.stringify(sandbox.out.map((u) => u.patente)), JSON.stringify(["TRAA55"]));
});
