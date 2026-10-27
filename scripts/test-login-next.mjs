// Ejecuta getNextPath real de js/login.js (sin navegador) y muestra
// cómo el parser WHATWG resuelve cada ?next= contra un origen.
import vm from "node:vm";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const origin = "https://fleetops.example";
const loginSource = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "..", "js", "login.js"),
    "utf8"
);

function element() {
    return {
        hidden: false,
        innerText: "",
        innerHTML: "",
        value: "",
        disabled: false,
        className: "",
        type: "",
        addEventListener() {},
        focus() {},
        appendChild() {},
        elements: {
            email: { value: "" },
            password: { value: "" }
        }
    };
}

function load(search) {
    const context = {
        window: {
            location: {
                search,
                origin,
                pathname: "/login.html",
                replace() {}
            }
        },
        document: {
            getElementById: element,
            querySelector: element
        },
        URL,
        URLSearchParams,
        console,
        supabaseClient: {
            auth: {
                getSession: async () => ({ data: { session: null } })
            },
            rpc: async () => ({ data: null, error: null })
        },
        getActiveOrganizationId() {
            return null;
        },
        setActiveOrganizationId() {},
        clearActiveOrganizationId() {},
        resolveOrganizationContext: async () => ({ organizations: [] })
    };
    vm.createContext(context);
    vm.runInContext(loginSource, context, { filename: "js/login.js" });
    return {
        next: context.getNextPath(),
        redirectTo: context.getAuthRedirectUrl()
    };
}

const cases = [
    { kind: "malicioso", search: "?next=/\\evil.com", expect: "dashboard.html" },
    { kind: "malicioso", search: "?next=/%5Cevil.com", expect: "dashboard.html" },
    { kind: "malicioso", search: "?next=/%09/evil.com", expect: "dashboard.html" },
    { kind: "malicioso", search: "?next=//evil.com", expect: "dashboard.html" },
    { kind: "malicioso", search: "?next=https://evil.com", expect: "dashboard.html" },
    { kind: "legitimo", search: "?next=/dashboard.html", expect: "/dashboard.html" },
    { kind: "legitimo", search: "?next=%2Fdashboard.html", expect: "/dashboard.html" },
    { kind: "legitimo", search: "?next=%2Froutes.html", expect: "/routes.html" },
    { kind: "legitimo", search: "?next=%2Fconductores.html", expect: "/conductores.html" },
    { kind: "legitimo", search: "?next=%2Fcustomer-dashboard.html", expect: "/customer-dashboard.html" },
    { kind: "legitimo", search: "?next=%2Ffleetops-admin.html", expect: "/fleetops-admin.html" },
    {
        kind: "legitimo",
        search: "?next=%2Froutes.html%3Ftab%3D1%23mapa",
        expect: "/routes.html?tab=1#mapa"
    },
    { kind: "ausente", search: "", expect: "dashboard.html" }
];

let failed = 0;
console.log(`origen ${origin}`);
for (const item of cases) {
    const decoded = new URLSearchParams(item.search).get("next");
    let resolved = null;
    if (decoded) {
        try {
            resolved = new URL(decoded, origin).href;
        } catch (error) {
            resolved = `ERR ${error.message}`;
        }
    }
    const result = load(item.search);
    const landed = new URL(result.next, origin);
    const redirect = new URL(result.redirectTo);
    const redirectNext = redirect.searchParams.get("next");
    const redirectLanded = new URL(redirectNext, origin);
    const pass =
        result.next === item.expect &&
        landed.origin === origin &&
        redirect.origin === origin &&
        redirectLanded.origin === origin &&
        redirectNext === result.next;
    if (!pass) {
        failed += 1;
    }
    console.log(JSON.stringify({
        kind: item.kind,
        search: item.search,
        decoded,
        resolved,
        getNextPath: result.next,
        expect: item.expect,
        redirectTo: result.redirectTo,
        pass
    }));
}

if (failed) {
    console.error(`fallaron ${failed}`);
    process.exit(1);
}
console.log(`ok ${cases.length}`);
