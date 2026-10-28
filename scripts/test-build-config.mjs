// El guard de scripts/build-config.mjs debe rechazar sb_secret_ y un JWT cuyo
// payload.role es service_role, y aceptar sb_publishable_ y un JWT anon.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("./build-config.mjs", import.meta.url));

function jwt(payload) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `${header}.${body}.sig`;
}

const serviceJwt = jwt({ iss: "supabase", ref: "projectref", role: "service_role" });
const anonJwt = jwt({ iss: "supabase", ref: "projectref", role: "anon" });

if (/service[_-]?role/i.test(serviceJwt) || /service[_-]?role/i.test("sb_secret_example")) {
  console.error("fixture invalido: el caso ya lo cubre el regex en claro");
  process.exit(1);
}

function run(key) {
  return spawnSync(process.execPath, [script], {
    env: {
      ...process.env,
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: key
    },
    encoding: "utf8"
  });
}

const cases = [
  { name: "sb_secret_", key: "sb_secret_example", ok: true },
  { name: "jwt service_role", key: serviceJwt, ok: false },
  { name: "sb_publishable_", key: "sb_publishable_example", ok: true },
  { name: "jwt anon", key: anonJwt, ok: true },
  { name: "texto service_role", key: "service_role", ok: false }
];

let failed = 0;
for (const item of cases) {
  const result = run(item.key);
  const pass = item.ok ? result.status === 0 : result.status === 1;
  if (!pass) failed += 1;
  console.log(JSON.stringify({
    name: item.name,
    status: result.status,
    pass,
    stderr: pass ? undefined : result.stderr
  }));
}

if (failed) {
  console.error(`fallaron ${failed}`);
  process.exit(1);
}
console.log(`ok ${cases.length}`);
