// Rework de #16: el enlace de mapa sale de lat/long (no de google_maps, que escribe el conductor)
// y reportes.html no escribe en tablas: solo submit_driver_report con ?viaje=. Datos ficticios.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function extract(src, name) {
  const i = src.indexOf(`function ${name}(`);
  assert.ok(i >= 0, `no existe ${name}`);
  let depth = 0;
  for (let k = src.indexOf("{", i); k < src.length; k++) {
    if (src[k] === "{") depth++;
    else if (src[k] === "}" && --depth === 0) return src.slice(i, k + 1);
  }
  throw new Error("llaves desbalanceadas");
}

test("mapsHref: solo coordenadas numéricas generan URL de Google Maps", () => {
  const sb = {};
  vm.runInNewContext(extract(fs.readFileSync("js/dashboard.js", "utf8"), "mapsHref") + "; this.f = mapsHref;", sb);
  assert.equal(sb.f(-33.45, -70.66), "https://www.google.com/maps?q=-33.45,-70.66");
  assert.equal(sb.f("javascript:alert(1)", 1), "");
  assert.equal(sb.f(null, null), "");
});

test("dashboard no pone google_maps del reporte en un href", () => {
  const src = fs.readFileSync("js/dashboard.js", "utf8");
  assert.ok(!/href="\$\{escapeHTML\(\s*(unit|operation)\.google_maps/.test(src));
});

test("app.js: el submit no inserta reportes ni lee la sesión para escribir", () => {
  const src = fs.readFileSync("js/app.js", "utf8");
  const submit = src.slice(src.indexOf("T-012: FLUJO QR"));
  assert.ok(!submit.includes('.from("reportes")'), "insert directo en reportes");
  assert.ok(!submit.includes("getOrCreateTrip("), "crea viajes fuera de la RPC");
  assert.ok(src.includes("if(!tripIdFromUrl){"), "falta el guard sin ?viaje=");
});
