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
const trips = [
  // retirado de ruta / ruta terminada (finalizar_viaje): org A
  { id: "t-a1", conductor_id: "c-a1", conductor: "Conductor Ficticio A", patente: "TRAA11", empresa_id: ORG_A, ruta: "Ruta A", fecha_finalizacion: "2026-10-30T10:00:00Z" },
  // finalizado de otra org: nunca debe aparecer en A
  { id: "t-b1", conductor_id: "c-b1", conductor: "Conductor Ficticio B", patente: "TRBB11", empresa_id: ORG_B, ruta: "Ruta B", fecha_finalizacion: "2026-10-30T10:00:00Z" },
];

test("conductores: un viaje finalizado/retirado no deja una fila suelta con el tracto", () => {
  const src = fs.readFileSync("js/conductores.js", "utf8");
  const completedPool = { innerHTML: "" };
  const ctx = { completedPool, escapeHTML, activeOrganizationId: ORG_A, returnedCompletedTripIds: new Set() };
  vm.runInNewContext(extract(src, "renderCompletedPools") + "; renderCompletedPools(trips);", { ...ctx, trips });
  const html = completedPool.innerHTML;
  fs.mkdirSync(process.env.SNAP_DIR || "/tmp", { recursive: true });
  fs.writeFileSync(`${process.env.SNAP_DIR || "/tmp"}/completed_pool.html`, html);
  assert.ok(!html.includes("TRAA11"), "queda una fila con la patente del tracto de org A");
  assert.ok(!html.includes("TRBB11"), "aparece un tracto de org B");
  assert.ok(!html.includes("route-driver"), "queda una fila por viaje finalizado");
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
