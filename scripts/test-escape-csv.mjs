// Lee escapeCSV de js/dashboard.js y comprueba el prefijo de fórmula.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const source = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "..", "js", "dashboard.js"),
    "utf8"
);

function extractFunction(name) {
    const start = source.indexOf(`function ${name}(`);
    if (start < 0) {
        throw new Error(`function ${name} no está en js/dashboard.js`);
    }

    let index = source.indexOf("{", start);
    let depth = 0;

    while (index < source.length) {
        const char = source[index];

        if (char === "{") {
            depth += 1;
        } else if (char === "}") {
            depth -= 1;
            if (depth === 0) {
                return source.slice(start, index + 1);
            }
        }

        index += 1;
    }

    throw new Error(`function ${name} no cierra`);
}

const escapeCSV = vm.runInNewContext(`${extractFunction("escapeCSV")}\nescapeCSV`);

const cases = [
    ["texto", "Patente ABCD12", "Patente ABCD12"],
    ["coma", "a,b", "\"a,b\""],
    ["comilla", "di \"hola\"", "\"di \"\"hola\"\"\""],
    ["igual", "=1+1", "\"'=1+1\""],
    ["mas", "+569", "\"'+569\""],
    ["menos", "-33.45", "\"'-33.45\""],
    ["arroba", "@cmd", "\"'@cmd\""],
    ["tab", "\tcmd", "\"'\tcmd\""],
    ["cr", "\rcmd", "\"'\rcmd\""],
    ["formula-coma", "=1,2", "\"'=1,2\""],
    ["formula-comilla", "=a\"b", "\"'=a\"\"b\""],
    ["igual-medio", "a=b", "a=b"],
    ["salto", "a\nb", "\"a\nb\""],
    ["vacio", "", ""],
    ["nulo", null, ""]
];

let failed = 0;

for (const [name, input, expected] of cases) {
    const actual = escapeCSV(input);
    const pass = actual === expected;
    if (!pass) {
        failed += 1;
    }
    console.log(JSON.stringify({ name, pass, actual, expected }));
}

if (failed) {
    console.error(`fallaron ${failed}`);
    process.exit(1);
}

console.log(`ok ${cases.length}`);
