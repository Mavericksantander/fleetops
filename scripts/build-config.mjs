#!/usr/bin/env node
// Build estático sin dependencias para Vercel.
// - Copia solo los archivos públicos (raíz *.html/*.css y js/) a dist/.
// - Genera dist/js/supabase-config.js desde SUPABASE_URL y SUPABASE_ANON_KEY.
// supabase/, migrations/, scripts/ y README nunca llegan a dist/.
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const out = join(root, "dist");

const url = (process.env.SUPABASE_URL || "").trim();
const anonKey = (process.env.SUPABASE_ANON_KEY || "").trim();

// sb_secret_ no contiene el texto "service_role". En un JWT, ese rol va en el
// payload base64, así que tampoco aparece en la clave en claro.
function jwtPayloadRole(key) {
  const parts = key.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) return "";
  for (const encoding of ["base64url", "base64"]) {
    try {
      const payload = JSON.parse(Buffer.from(parts[1], encoding).toString("utf8"));
      if (payload && typeof payload.role === "string") return payload.role.trim();
    } catch {
      // el segmento no es JSON en esta codificación
    }
  }
  return "";
}

function isPrivilegedSupabaseKey(key) {
  if (/^sb_secret_/i.test(key)) return true;
  if (/service[_-]?role/i.test(key)) return true;
  return /service[_-]?role/i.test(jwtPayloadRole(key));
}

const missing = [];
if (!url) missing.push("SUPABASE_URL");
if (!anonKey) missing.push("SUPABASE_ANON_KEY");
if (missing.length) {
  console.error(`[build-config] ERROR: faltan variables de entorno: ${missing.join(", ")}.`);
  console.error("[build-config] Configúralas en Vercel > Project Settings > Environment Variables.");
  process.exit(1);
}
if (!/^https:\/\/[^\s/]+/.test(url)) {
  console.error(`[build-config] ERROR: SUPABASE_URL debe empezar con https:// (recibido: "${url}").`);
  process.exit(1);
}
if (isPrivilegedSupabaseKey(anonKey)) {
  console.error("[build-config] ERROR: SUPABASE_ANON_KEY parece una clave privilegiada (service_role o sb_secret_). Usa la anon/publishable key.");
  process.exit(1);
}

rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, "js"), { recursive: true });

for (const f of readdirSync(root)) {
  if (/\.(html|css|ico|png|svg|webmanifest)$/i.test(f)) cpSync(join(root, f), join(out, f));
}
for (const f of readdirSync(join(root, "js"))) {
  if (f === "supabase-config.js" || f === "supabase-config.example.js") continue;
  cpSync(join(root, "js", f), join(out, "js", f));
}
for (const dir of ["img", "images", "assets", "fonts"]) {
  if (existsSync(join(root, dir))) cpSync(join(root, dir), join(out, dir), { recursive: true });
}

const content = `window.FLEETOPS_SUPABASE_CONFIG = Object.freeze({
  url: ${JSON.stringify(url)},
  anonKey: ${JSON.stringify(anonKey)}
});
`;
writeFileSync(join(out, "js", "supabase-config.js"), content);
console.log(`[build-config] OK: dist/ generado, js/supabase-config.js apunta a ${url}`);
