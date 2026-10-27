const customerOperationsList = document.getElementById("customerOperationsList");
const customerEmptyState = document.getElementById("customerEmptyState");
const customerError = document.getElementById("customerError");
const customerName = document.getElementById("customerName");
const customerLastUpdate = document.getElementById("customerLastUpdate");
const connectionIndicator = document.getElementById("connectionIndicator");
const connectionText = document.getElementById("connectionText");
const logoutButton = document.getElementById("logoutButton");
let customerRefreshTimer = null;
let customerRefreshInProgress = false;
let activeCustomerOrganizationId = null;

function setConnectionStatus(connected) {
    if (!connectionIndicator || !connectionText) {
        return;
    }

    connectionIndicator.classList.remove("connected", "disconnected");
    if (connected) {
        connectionIndicator.classList.add("connected");
        connectionText.innerText = "CONNECTED";
        return;
    }

    connectionIndicator.classList.add("disconnected");
    connectionText.innerText = "DATABASE ERROR";
}

function escapeHTML(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function formatTimestamp(value) {
    if (!value) {
        return "--";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return "--";
    }

    return date.toLocaleString("es-CL", {
        dateStyle: "short",
        timeStyle: "short"
    });
}

function formatElapsed(value) {
    if (!value) {
        return "--";
    }

    const timestamp = new Date(value).getTime();
    if (!Number.isFinite(timestamp)) {
        return "--";
    }
    const elapsedMinutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
    const hours = Math.floor(elapsedMinutes / 60);
    const minutes = elapsedMinutes % 60;
    return hours ? `${hours} h ${minutes} min` : `${minutes} min`;
}

function getCustomerStatusClass(status) {
    const normalizedStatus = String(status ?? "")
        .trim()
        .toLocaleLowerCase("es")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");

    if (normalizedStatus.startsWith("incid")) {
        return "red";
    }

    switch (normalizedStatus) {
        case "en ruta":
            return "green";
        case "esperando carga":
            return "yellow";
        case "cargando":
            return "purple";
        case "esperando descarga":
            return "orange";
        case "descargando":
            return "blue";
        case "finalizado":
            return "gray";
        default:
            return "gray";
    }
}

function renderSummary(operations) {
    const summaryNodes = {
        summaryActive: document.getElementById("summaryActive"),
        summaryEnRuta: document.getElementById("summaryEnRuta"),
        summaryEsperandoCarga: document.getElementById("summaryEsperandoCarga"),
        summaryCargando: document.getElementById("summaryCargando"),
        summaryDescargando: document.getElementById("summaryDescargando"),
        summaryIncidentes: document.getElementById("summaryIncidentes")
    };

    const counts = {
        summaryActive: operations.filter(operation =>
            operation.trip_status && operation.trip_status !== "Finalizado"
        ).length,
        summaryEnRuta: 0,
        summaryEsperandoCarga: 0,
        summaryCargando: 0,
        summaryDescargando: 0,
        summaryIncidentes: 0
    };

    operations.forEach(function (operation) {
        const status = operation.trip_status || "Sin estado";
        if (status === "En ruta") {
            counts.summaryEnRuta += 1;
        }
        if (status === "Esperando carga") {
            counts.summaryEsperandoCarga += 1;
        }
        if (status === "Cargando") {
            counts.summaryCargando += 1;
        }
        if (status === "Descargando") {
            counts.summaryDescargando += 1;
        }
        if (status === "Incidente") {
            counts.summaryIncidentes += 1;
        }
    });

    summaryNodes.summaryActive.innerText = counts.summaryActive;
    summaryNodes.summaryEnRuta.innerText = counts.summaryEnRuta;
    summaryNodes.summaryEsperandoCarga.innerText = counts.summaryEsperandoCarga;
    summaryNodes.summaryCargando.innerText = counts.summaryCargando;
    summaryNodes.summaryDescargando.innerText = counts.summaryDescargando;
    summaryNodes.summaryIncidentes.innerText = counts.summaryIncidentes;
}

function renderOperations(operations, reportsByTrip) {
    if (!customerOperationsList) {
        return;
    }

    renderSummary(operations || []);

    if (!operations || operations.length === 0) {
        customerOperationsList.innerHTML = "";
        if (customerEmptyState) {
            customerEmptyState.hidden = false;
        }
        return;
    }

    if (customerEmptyState) {
        customerEmptyState.hidden = true;
    }

    customerOperationsList.innerHTML = operations.map(function (operation) {
        const status = operation.trip_status || "Sin estado";
        const statusClass = getCustomerStatusClass(status);
        const lastReport = operation.last_report_at || operation.fecha_inicio || "--";
        const observation = operation.last_report_observacion || "Sin observación operativa";
        const routeLabel = operation.route_label || operation.route_name || "Ruta sin nombre";
        const tripIdLabel = operation.trip_id ? String(operation.trip_id).slice(0, 8).toUpperCase() : "SIN ID";
        const reports = reportsByTrip.get(operation.trip_id) || [];
        const timeline = reports.length
            ? reports.map(report => {
                const latitude = Number(report.latitud);
                const longitude = Number(report.longitud);
                const hasCoordinates = report.latitud != null &&
                    report.longitud != null &&
                    Number.isFinite(latitude) &&
                    Number.isFinite(longitude);
                const location = hasCoordinates
                    ? `https://www.google.com/maps?q=${latitude},${longitude}`
                    : "";
                return `
                    <div class="profile-timeline-event">
                        <strong>${escapeHTML(report.estado || "SIN ESTADO")}</strong>
                        <div class="timeline-time">${escapeHTML(formatTimestamp(report.timestamp))}</div>
                        ${report.incident_category ? `<div class="data-value">Incidente: ${escapeHTML(report.incident_category)}</div>` : ""}
                        ${report.observacion ? `<div class="timeline-observation">${escapeHTML(report.observacion)}</div>` : ""}
                        ${location ? `<a class="back-link" href="${escapeHTML(location)}" target="_blank" rel="noopener noreferrer">VER UBICACIÓN</a>` : ""}
                    </div>
                `;
            }).join("")
            : '<div class="profile-document-status">Sin reportes registrados.</div>';

        return `
            <article class="driver-card">
                <div class="driver-card-header">
                    <div>
                        <div class="driver-card-id">VIAJE ${escapeHTML(tripIdLabel)}</div>
                        <div class="driver-card-name">${escapeHTML(routeLabel)}</div>
                    </div>
                    <div class="driver-state ${statusClass}">${escapeHTML(status)}</div>
                </div>

                <div class="profile-grid">
                    <div class="data-row"><span class="data-label">RUTA</span><span class="data-value">${escapeHTML(routeLabel)}</span></div>
                    <div class="data-row"><span class="data-label">UNIDAD / PATENTE</span><span class="data-value">${escapeHTML(operation.patente || "--")}</span></div>
                    <div class="data-row"><span class="data-label">ESTADO</span><span class="data-value">${escapeHTML(status)}</span></div>
                    <div class="data-row"><span class="data-label">ÚLTIMO REPORTE</span><span class="data-value">${escapeHTML(formatTimestamp(lastReport))}</span></div>
                    <div class="data-row"><span class="data-label">TIEMPO EN ESTADO</span><span class="data-value">${escapeHTML(formatElapsed(operation.last_report_at || operation.fecha_inicio))}</span></div>
                    <div class="data-row"><span class="data-label">OBSERVACIÓN</span><span class="data-value">${escapeHTML(observation)}</span></div>
                    <div class="data-row"><span class="data-label">TIMESTAMP</span><span class="data-value">${escapeHTML(formatTimestamp(operation.last_report_at || operation.fecha_inicio))}</span></div>
                </div>
                <details class="customer-trip-timeline">
                    <summary>HISTORIAL OPERACIONAL (${reports.length})</summary>
                    <div class="customer-trip-timeline-list">${timeline}</div>
                </details>
            </article>
        `;
    }).join("");
}

async function refreshCustomerOperations() {
    if (customerRefreshInProgress) {
        return;
    }

    customerRefreshInProgress = true;
    try {
        const { data: operations, error: operationsError } = await supabaseClient.rpc(
            "get_customer_visible_operations_for_org",
            { p_organization_id: activeCustomerOrganizationId }
        );

        if (operationsError) {
            throw operationsError;
        }

        const visibleOperations = operations || [];
        const reportsByTrip = new Map();
        const visibleTripIds = visibleOperations.map(operation => operation.trip_id).filter(Boolean);
        if (visibleTripIds.length) {
            const { data: reports, error: reportsError } = await supabaseClient
                .from("reportes")
                .select("viaje_id, estado, incident_category, latitud, longitud, google_maps, observacion, timestamp")
                .in("viaje_id", visibleTripIds)
                .order("timestamp", { ascending: false });

            if (reportsError) {
                throw reportsError;
            }

            (reports || []).forEach(report => {
                const current = reportsByTrip.get(report.viaje_id) || [];
                current.push(report);
                reportsByTrip.set(report.viaje_id, current);
            });
        }

        renderOperations(visibleOperations, reportsByTrip);
        customerLastUpdate.innerText = new Date().toLocaleString("es-CL", {
            dateStyle: "short",
            timeStyle: "short"
        });
        setConnectionStatus(true);
        customerError.innerText = "";
    } finally {
        customerRefreshInProgress = false;
    }
}

async function initializeCustomerDashboard() {
    const {
        data: sessionData,
        error: sessionError
    } = await supabaseClient.auth.getSession();

    if (sessionError) {
        throw sessionError;
    }

    if (!sessionData.session) {
        window.location.replace("login.html?next=customer-dashboard.html");
        return;
    }

    const context = await resolveOrganizationContext();
    if (!context.session || !context.activeOrganization) {
        window.location.replace("login.html?next=customer-dashboard.html");
        return;
    }
    activeCustomerOrganizationId = context.activeOrganization.id;

    const { data: customerRows, error: customerError } = await supabaseClient.rpc(
        "get_customer_context_for_org",
        { p_organization_id: context.activeOrganization.id }
    );
    if (customerError) {
        throw customerError;
    }
    const customerContext = Array.isArray(customerRows) ? customerRows[0] : customerRows;
    if (!customerContext || customerContext.organization_id !== context.activeOrganization.id) {
        const { error: signOutError } = await supabaseClient.auth.signOut();
        if (signOutError) {
            throw signOutError;
        }
        window.location.replace("login.html");
        return;
    }

    if (customerContext.role !== "customer") {
        window.location.replace("dashboard.html");
        return;
    }
    customerName.innerText = customerContext.customer_name || "CLIENTE";

    await refreshCustomerOperations();
    customerRefreshTimer = window.setInterval(function () {
        refreshCustomerOperations().catch(function (error) {
            console.error("PRÆTOR FleetOps: no fue posible actualizar las operaciones del cliente", error);
            setConnectionStatus(false);
            customerError.innerText = error.message || "No fue posible actualizar las operaciones.";
        });
    }, 30000);
}

if (logoutButton) {
    logoutButton.addEventListener("click", async function () {
        if (customerRefreshTimer) {
            window.clearInterval(customerRefreshTimer);
            customerRefreshTimer = null;
        }
        const { error } = await supabaseClient.auth.signOut();
        if (error) {
            customerError.innerText = error.message || "No fue posible cerrar la sesión.";
            return;
        }
        window.location.replace("login.html");
    });
}

initializeCustomerDashboard().catch(function (error) {
    console.error("PRÆTOR FleetOps: no fue posible cargar el dashboard de cliente", error);
    setConnectionStatus(false);
    if (customerError) {
        customerError.innerText = error.message || "No fue posible cargar la información autorizada.";
    }
});
