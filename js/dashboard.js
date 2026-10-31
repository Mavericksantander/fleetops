
// =====================================================
// ELEMENTOS DOM
// =====================================================

const fleetContainer =
    document.getElementById("fleetContainer");

const lastUpdate =
    document.getElementById("lastUpdate");

const connectionIndicator =
    document.getElementById("connectionIndicator");

const connectionText =
    document.getElementById("connectionText");

const driversContainer =
    document.getElementById("driversContainer");

const driverCount =
    document.getElementById("driverCount");

const driverProfileModal =
    document.getElementById("driverProfileModal");

const driverProfileContent =
    document.getElementById("driverProfileContent");

const profileDriverId =
    document.getElementById("profileDriverId");

let activeOrganizationId = null;
let dashboardAccessValid = false;
let dashboardPollingId = null;
const STALE_REPORT_THRESHOLD_MS = 6 * 60 * 60 * 1000;

// =====================================================
// VALIDACIÓN
// =====================================================

if (!fleetContainer) {

    console.error(
        "FLEETOPS ERROR: #fleetContainer no encontrado."
    );

    throw new Error(
        "FleetOps Dashboard: contenedor no encontrado."
    );

}

async function initializeOperatorSession() {

    dashboardAccessValid = false;

    const context = await resolveOrganizationContext();

    if (!context.session) {
        if (dashboardPollingId) {
            clearInterval(dashboardPollingId);
            dashboardPollingId = null;
        }
        window.location.replace(
            `login.html?next=${encodeURIComponent(window.location.pathname)}`
        );
        return false;
    }

    if (!context.activeOrganization) {
        if (dashboardPollingId) {
            clearInterval(dashboardPollingId);
            dashboardPollingId = null;
        }
        window.location.replace(
            `login.html?next=${encodeURIComponent(window.location.pathname)}`
        );
        return false;
    }

    const {
        data: memberships,
        error: membershipError
    } = await supabaseClient
        .from("organization_members")
        .select("role")
        .eq("organization_id", context.activeOrganization.id)
        .eq("user_id", context.session.user.id)
        .limit(1);

    if (membershipError) {
        throw membershipError;
    }

    if (memberships && memberships[0] && memberships[0].role === "customer") {
        window.location.replace("customer-dashboard.html");
        return false;
    }

    activeOrganizationId = context.activeOrganization.id;
    dashboardAccessValid = true;

    return true;

}

document
    .querySelectorAll(".nav-button[data-view]")
    .forEach(
        button => {

            if (button.disabled) {
                return;
            }

            button.addEventListener(
                "click",
                function () {

                    document
                        .querySelectorAll(".nav-button[data-view]")
                        .forEach(
                            navButton => {
                                navButton.classList.remove("active");
                            }
                        );

                    document
                        .querySelectorAll(".view-panel")
                        .forEach(
                            panel => {
                                panel.hidden =
                                    panel.id !== this.dataset.view;
                            }
                        );

                    this.classList.add("active");

                }
            );

        }
    );


// =====================================================
// ESTADO
// =====================================================

let activeFilter = "all";

let currentUnits = [];

let currentConductors = [];

let currentConductorDocuments = [];

let currentTractoDocuments = [];

let currentTractos = [];


// =====================================================
// CONEXIÓN
// =====================================================

function setConnectionStatus(connected) {

    if (
        !connectionIndicator ||
        !connectionText
    ) {
        return;
    }

    connectionIndicator.classList.remove(
        "connected",
        "disconnected"
    );

    if (connected) {

        connectionIndicator.classList.add(
            "connected"
        );

        connectionText.innerText =
            "CONNECTED";

    }

    else {

        connectionIndicator.classList.add(
            "disconnected"
        );

        connectionText.innerText =
            "DATABASE ERROR";

    }

}


// =====================================================
// NORMALIZAR PATENTE
// =====================================================

function normalizePlate(value) {

    return String(value || "")
        .replace(/[^a-zA-Z0-9]/g, "")
        .toUpperCase();

}


// =====================================================
// FORMATEAR PATENTE
// =====================================================

function formatPlate(plate) {

    const normalized =
        normalizePlate(plate);

    return normalized || "SIN PATENTE";

}


// =====================================================
// ESCAPAR HTML
// =====================================================

function escapeHTML(value) {

    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");

}

// google_maps lo escribe el conductor y la RPC solo limita el largo.
function mapsHref(latitud, longitud) {

    const latitude = Number(latitud);
    const longitude = Number(longitud);
    const hasCoordinates = latitud != null &&
        longitud != null &&
        Number.isFinite(latitude) &&
        Number.isFinite(longitude);

    return hasCoordinates
        ? `https://www.google.com/maps?q=${latitude},${longitude}`
        : "";

}

function renderConductors(conductors) {

    if (!driversContainer) {
        return;
    }

    if (driverCount) {
        driverCount.innerText = conductors.length;
    }

    if (conductors.length === 0) {
        driversContainer.innerHTML = `
            <div class="empty-state">
                <div class="empty-code">NO DATA</div>
                <div class="empty-title">SIN CONDUCTORES REGISTRADOS</div>
                <div class="empty-text">Todavía no existen conductores disponibles en FleetOps.</div>
            </div>
        `;
        return;
    }

    driversContainer.innerHTML = conductors.map(function (conductor) {
        return `
            <article class="driver-card">
                <div class="driver-card-header">
                    <div>
                        <div class="driver-card-id">${escapeHTML(conductor.driver_id)}</div>
                        <div class="driver-card-name">${escapeHTML(conductor.nombre)}</div>
                    </div>
                    <div class="driver-state">${escapeHTML(conductor.estado || "SIN ESTADO")}</div>
                </div>
                <div class="driver-data">
                    <div class="data-row">
                        <span class="data-label">RUT</span>
                        <span class="data-value">${escapeHTML(conductor.rut || "--")}</span>
                    </div>

                    <div class="data-row">
                        <span class="data-label">LICENCIA</span>
                        <span class="data-value">${escapeHTML(conductor.licencia || "--")}</span>
                    </div>
                    <div class="data-row">
                        <span class="data-label">TELÉFONO</span>
                        <span class="data-value">${escapeHTML(conductor.telefono || "--")}</span>
                    </div>
                    <div class="data-row">
                        <span class="data-label">TIPO DE LICENCIA</span>
                        <span class="data-value">${escapeHTML(conductor.tipo_licencia || "--")}</span>
                    </div>
                    <div class="data-row">
                        <span class="data-label">CIUDAD</span>
                        <span class="data-value">${escapeHTML(conductor.ciudad || "--")}</span>
                    </div>
                    <div class="data-row">
                        <span class="data-label">PATENTE HABITUAL</span>
                        <span class="data-value">${escapeHTML(conductor.patente_habitual || "--")}</span>
                    </div>
                    <div class="data-row">
                        <span class="data-label">FECHA DE REGISTRO</span>
                        <span class="data-value">${escapeHTML(formatTimestamp(conductor.fecha_registro))}</span>
                    </div>
                </div>
                <button type="button" class="driver-profile-button" data-driver-id="${escapeHTML(conductor.id)}">VER PERFIL OPERATIVO</button>
            </article>
        `;
    }).join("");

}

function renderProfileTimeline(timeline) {

    if (!timeline || timeline.length === 0) {
        return `<div class="profile-document-status">Sin eventos registrados.</div>`;
    }

    return timeline.map(function (event) {
        return `
            <div class="profile-timeline-event">
                <strong>${escapeHTML(event.estado || "SIN ESTADO")}</strong>
                <div class="timeline-time">${escapeHTML(formatTimestamp(event.start))}</div>
                <div class="data-value">Duración: ${escapeHTML(event.duration || "--")}</div>
                ${event.observacion ? `<div class="timeline-observation">${escapeHTML(event.observacion)}</div>` : ""}
            </div>
        `;
    }).join("");

}

function openDriverProfile(driverId) {

    const conductor =
        currentConductors.find(function (item) {
            return item.id === driverId;
        });

    if (!conductor || !driverProfileModal || !driverProfileContent) {
        return;
    }

    const operation =
        currentUnits.find(function (unit) {
            return unit.conductor_id === driverId && unit.estado !== "Finalizado";
        }) ||
        currentUnits.find(function (unit) {
            return unit.conductor_id === driverId;
        });

    const conductorDocuments =
        currentConductorDocuments.filter(function (document) {
            return document.conductor_id === driverId;
        });

    const assignedTractor =
        conductor.tracto_id
            ? currentTractos.find(function (tractor) {
                return tractor.id === conductor.tracto_id;
            })
            : null;

    const tractorDocuments =
        assignedTractor
            ? currentTractoDocuments.filter(function (document) {
                return document.tracto_id === assignedTractor.id;
            })
            : [];

    const profileMapsHref = operation
        ? mapsHref(operation.latitud, operation.longitud)
        : "";

    profileDriverId.innerText =
        conductor.driver_id || "SIN DRIVER ID";

    driverProfileContent.innerHTML = `
        <section class="profile-section">
            <div class="profile-section-title">IDENTIDAD</div>
            <div class="profile-grid">
                <div class="data-row"><span class="data-label">NOMBRE</span><span class="data-value">${escapeHTML(conductor.nombre)}</span></div>
                <div class="data-row"><span class="data-label">RUT</span><span class="data-value">${escapeHTML(conductor.rut || "--")}</span></div>
                <div class="data-row"><span class="data-label">TELÉFONO</span><span class="data-value">${escapeHTML(conductor.telefono || "--")}</span></div>
                <div class="data-row"><span class="data-label">CIUDAD</span><span class="data-value">${escapeHTML(conductor.ciudad || "--")}</span></div>
                <div class="data-row"><span class="data-label">TIPO DE LICENCIA</span><span class="data-value">${escapeHTML(conductor.tipo_licencia || "--")}</span></div>
                <div class="data-row"><span class="data-label">ESTADO</span><span class="data-value">${escapeHTML(conductor.estado || "--")}</span></div>
            </div>
        </section>
        <section class="profile-section">
            <div class="profile-section-title">EQUIPO</div>
            <div class="profile-grid">
                <div class="data-row"><span class="data-label">PATENTE</span><span class="data-value">${escapeHTML(assignedTractor?.patente || conductor.patente_habitual || "--")}</span></div>
                <div class="data-row"><span class="data-label">ESTADO</span><span class="data-value">${escapeHTML(assignedTractor?.estado || "--")}</span></div>
            </div>
        </section>
        <section class="profile-section">
            <div class="profile-section-title">DOCUMENTACIÓN</div>
            <div class="profile-grid">
                <div class="profile-document-status ${conductor.licencia ? "available" : ""}">
                    LICENCIA: ${escapeHTML(conductor.licencia || "SIN REGISTRO")}
                </div>
                <div class="profile-document-status ${conductorDocuments.length ? "available" : ""}">
                    ARCHIVOS DE LICENCIA: ${conductorDocuments.length || "SIN ARCHIVOS"}
                </div>
                ${conductorDocuments.map(function (document) {
                    return `<div class="profile-document-status">${escapeHTML(document.tipo_documento)} · ${escapeHTML(document.estado_revision)} · ${escapeHTML(document.nombre_archivo || document.storage_path)}</div>`;
                }).join("")}
            </div>
        </section>
        <section class="profile-section">
            <div class="profile-section-title">OPERACIÓN ACTUAL</div>
            ${operation ? `
                <div class="profile-grid">
                    <div class="data-row"><span class="data-label">EQUIPO / PATENTE</span><span class="data-value">${escapeHTML(operation.patente || "--")}</span></div>
                    <div class="data-row"><span class="data-label">ESTADO</span><span class="data-value">${escapeHTML(operation.estado || "--")}</span></div>
                    <div class="data-row"><span class="data-label">RUTA</span><span class="data-value">${escapeHTML(operation.ruta || "--")}</span></div>
                    <div class="data-row"><span class="data-label">EMPRESA</span><span class="data-value">${escapeHTML(operation.empresa || "--")}</span></div>
                    <div class="data-row"><span class="data-label">ÚLTIMO EVENTO</span><span class="data-value">${escapeHTML(formatTimestamp(operation.timestamp))}</span></div>
                    <div class="data-row"><span class="data-label">DURACIÓN</span><span class="data-value">${escapeHTML(operation.estado === "Finalizado" ? "--" : formatLiveDuration(operation.timestamp || operation.fecha_inicio))}</span></div>
                </div>
                <div class="profile-section-title">TIMELINE</div>
                ${renderProfileTimeline(operation.timeline)}
                <div class="profile-section-title">DOCUMENTOS DEL EQUIPO</div>
                ${tractorDocuments.length
                    ? tractorDocuments.map(function (document) {
                        return `<div class="profile-document-status">${escapeHTML(document.tipo_documento)} · ${escapeHTML(document.estado_revision)} · ${escapeHTML(document.nombre_archivo || document.storage_path)}</div>`;
                    }).join("")
                    : `<div class="profile-document-status">Sin documentos de equipo registrados.</div>`}
                ${profileMapsHref ? `<a class="maps-button" href="${escapeHTML(profileMapsHref)}" target="_blank" rel="noopener noreferrer">VER EN GOOGLE MAPS</a>` : ""}
            ` : `<div class="profile-document-status">Sin operación actual asociada.</div>`}
        </section>
    `;

    driverProfileModal.hidden = false;

}

function closeDriverProfile() {

    if (driverProfileModal) {
        driverProfileModal.hidden = true;
    }

}

document.addEventListener("click", function (event) {

    const profileButton =
        event.target.closest(".driver-profile-button");

    if (profileButton) {
        openDriverProfile(profileButton.dataset.driverId);
        return;
    }

    if (event.target === driverProfileModal) {
        closeDriverProfile();
    }

});

document
    .getElementById("closeDriverProfile")
    ?.addEventListener("click", closeDriverProfile);

document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
        closeDriverProfile();
    }
});


// =====================================================
// CLASE CSS DEL ESTADO
// =====================================================

function getStatusClass(status) {

    switch (status) {

        case "En ruta":
            return "green";

        case "Esperando carga":
            return "yellow";

        case "Cargando":
            return "purple";

        case "Esperando descarga":
            return "orange";

        case "Descargando":
            return "blue";

        case "Finalizado":
            return "gray";

        case "Incidente":
            return "red";

        default:
            return "gray";

    }

}


// =====================================================
// PRIORIDAD OPERACIONAL
// =====================================================

function getStatusPriority(status) {

    switch (status) {

        case "Incidente":
            return 1;

        case "En ruta":
            return 2;

        case "Esperando carga":
            return 3;

        case "Cargando":
            return 4;

        case "Esperando descarga":
            return 5;

        case "Descargando":
            return 6;

        case "Finalizado":
            return 7;

        default:
            return 99;

    }

}


// =====================================================
// FECHA
// =====================================================

function formatTimestamp(timestamp) {

    if (!timestamp) {
        return "--";
    }

    const date =
        new Date(timestamp);

    if (
        Number.isNaN(
            date.getTime()
        )
    ) {
        return "--";
    }

    return date.toLocaleString(
        "es-CL",
        {
            day: "2-digit",
            month: "2-digit",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit"
        }
    );

}


// =====================================================
// DURACIÓN
// =====================================================

function formatDurationCompact(
    start,
    end
) {

    if (!start || !end) {
        return "--";
    }

    const startDate =
        new Date(start);

    const endDate =
        new Date(end);

    const milliseconds =
        endDate - startDate;

    if (
        !Number.isFinite(milliseconds) ||
        milliseconds < 0
    ) {
        return "--";
    }

    const totalSeconds =
        Math.floor(
            milliseconds / 1000
        );

    const hours =
        Math.floor(
            totalSeconds / 3600
        );

    const minutes =
        Math.floor(
            (
                totalSeconds % 3600
            ) / 60
        );

    const seconds =
        totalSeconds % 60;

    return (
        `${String(hours).padStart(2, "0")}:` +
        `${String(minutes).padStart(2, "0")}:` +
        `${String(seconds).padStart(2, "0")}`
    );

}


// =====================================================
// DURACIÓN EN TIEMPO REAL
// =====================================================

function formatLiveDuration(start) {

    if (!start) {
        return "--";
    }

    const startDate =
        new Date(start);

    if (
        Number.isNaN(
            startDate.getTime()
        )
    ) {
        return "--";
    }

    return formatDurationCompact(
        start,
        new Date().toISOString()
    );

}


// =====================================================
// HISTORIAL DE ESTADOS
// =====================================================

function buildEventTimeline(
    reports,
    trip,
    conductorsById
) {

    if (!trip) {
        return [];
    }

    const tripReports =
        reports
            .filter(
                report =>
                    report.viaje_id ===
                    trip.id
            )
            .sort(
                (a, b) =>
                    new Date(a.timestamp) -
                    new Date(b.timestamp)
            );

    if (
        tripReports.length === 0
    ) {
        return [];
    }


    return tripReports.map(
        (report, index) => {

            const nextReport =
                tripReports[index + 1];

            const start =
                report.timestamp;

            let end = null;


            if (nextReport) {

                end =
                    nextReport.timestamp;

            }

            else if (
                trip.fecha_finalizacion
            ) {

                end =
                    trip.fecha_finalizacion;

            }


            return {

                ...report,

                actor_label:
                    report.actor_type === "operator"
                        ? `OPERADOR · ${report.actor_user_id || "ID NO DISPONIBLE"}`
                        : report.actor_conductor_id &&
                            conductorsById[report.actor_conductor_id]
                            ? `CONDUCTOR · ${conductorsById[report.actor_conductor_id].driver_id || "ID NO DISPONIBLE"}`
                            : report.actor_type === "legacy"
                                ? "REGISTRO ANTIGUO · ACTOR NO REGISTRADO"
                                : "CONDUCTOR · IDENTIDAD NO VERIFICADA",

                start,

                end,

                duration:
                    end
                        ? formatDurationCompact(
                            start,
                            end
                        )
                        : "--"

            };

        }
    );

}


// =====================================================
// RESUMEN
// =====================================================

function updateSummary(units) {

    const total =
        document.getElementById("totalUnits");

    const active =
        document.getElementById("activeUnits");

    const route =
        document.getElementById("routeUnits");

    const waiting =
        document.getElementById("waitingUnits");

    const loading =
        document.getElementById("loadingUnits");

    const incidents =
        document.getElementById("incidentUnits");


    const activeCount =
        units.filter(
            unit =>
                unit.estado !==
                "Finalizado"
        ).length;


    const routeCount =
        units.filter(
            unit =>
                unit.estado ===
                "En ruta"
        ).length;


    const waitingCount =
        units.filter(
            unit =>
                unit.estado ===
                    "Esperando carga" ||
                unit.estado ===
                    "Esperando descarga"
        ).length;


    const loadingCount =
        units.filter(
            unit =>
                unit.estado ===
                    "Cargando" ||
                unit.estado ===
                    "Descargando"
        ).length;


    const incidentCount =
        units.filter(
            unit =>
                unit.estado ===
                "Incidente"
        ).length;


    if (total) {
        total.innerText =
            units.length;
    }

    if (active) {
        active.innerText =
            activeCount;
    }

    if (route) {
        route.innerText =
            routeCount;
    }

    if (waiting) {
        waiting.innerText =
            waitingCount;
    }

    if (loading) {
        loading.innerText =
            loadingCount;
    }

    if (incidents) {
        incidents.innerText =
            incidentCount;
    }

}


// =====================================================
// CONTADORES DE FILTROS
// =====================================================

function updateFilterCounts(units) {

    const count =
        status =>
            units.filter(
                unit =>
                    unit.estado ===
                    status
            ).length;


    const elements = {

        all:
            document.getElementById(
                "filterAllCount"
            ),

        route:
            document.getElementById(
                "filterRouteCount"
            ),

        waitingLoad:
            document.getElementById(
                "filterWaitingLoadCount"
            ),

        loading:
            document.getElementById(
                "filterLoadingCount"
            ),

        waitingUnload:
            document.getElementById(
                "filterWaitingUnloadCount"
            ),

        unloading:
            document.getElementById(
                "filterUnloadingCount"
            ),

        finished:
            document.getElementById(
                "filterFinishedCount"
            ),

        incident:
            document.getElementById(
                "filterIncidentCount"
            )

    };


    if (elements.all) {
        elements.all.innerText =
            units.length;
    }

    if (elements.route) {
        elements.route.innerText =
            count("En ruta");
    }

    if (elements.waitingLoad) {
        elements.waitingLoad.innerText =
            count("Esperando carga");
    }

    if (elements.loading) {
        elements.loading.innerText =
            count("Cargando");
    }

    if (elements.waitingUnload) {
        elements.waitingUnload.innerText =
            count("Esperando descarga");
    }

    if (elements.unloading) {
        elements.unloading.innerText =
            count("Descargando");
    }

    if (elements.finished) {
        elements.finished.innerText =
            count("Finalizado");
    }

    if (elements.incident) {
        elements.incident.innerText =
            count("Incidente");
    }

}


// =====================================================
// TARJETA DE UNIDAD
// =====================================================

function createUnitCard(unit) {

    const card =
        document.createElement(
            "div"
        );


    const statusClass =
        getStatusClass(
            unit.estado
        );


    card.className =
        `unit-card ${statusClass}`;


    const plate =
        formatPlate(
            unit.patente
        );


    const conductor =
        unit.conductor ||
        "SIN CONDUCTOR";

    const driverId =
        unit.driver_id ||
        "LEGACY · SIN DRIVER ID";


    const empresa =
        unit.empresa ||
        "SIN EMPRESA";


    const ruta =
        unit.ruta ||
        "SIN RUTA";


    const estado =
        unit.estado ||
        "SIN ESTADO";


    const observacion =
        unit.observacion ||
        "Sin reporte operacional";


    const timestamp =
        formatTimestamp(
            unit.timestamp ||
            unit.fecha_inicio
        );


    const liveDuration =
        unit.estado === "Finalizado"
            ? "--"
            : formatLiveDuration(
                unit.timestamp ||
                unit.fecha_inicio
            );

    const lastActivity =
        unit.timestamp ||
        unit.fecha_inicio;
    const isStale =
        unit.estado !== "Finalizado" &&
        lastActivity &&
        Date.now() - new Date(lastActivity).getTime() >= STALE_REPORT_THRESHOLD_MS;
    const staleDuration =
        isStale
            ? formatLiveDuration(lastActivity)
            : "";


    const mapsURL =
        mapsHref(
            unit.latitud,
            unit.longitud
        );

    let mapsButton = "";


    if (mapsURL) {

        mapsButton = `

            <a
                class="maps-button"
                href="${escapeHTML(
                    mapsURL
                )}"
                target="_blank"
                rel="noopener noreferrer">

                VER EN GOOGLE MAPS

            </a>

        `;

    }


    const timelineHTML =
        unit.timeline &&
        unit.timeline.length > 0
            ? `

                <div class="trip-timeline">

                    <div class="timeline-title">
                        HISTORIAL DE ESTADOS
                    </div>

                    ${unit.timeline.map(
                        event => {

                            const eventClass =
                                getStatusClass(
                                    event.estado
                                );


                            return `

                                <div class="timeline-event">

                                    <div
                                        class="timeline-marker ${eventClass}">
                                    </div>


                                    <div
                                        class="timeline-content">

                                        <div
                                            class="timeline-header">

                                            <span
                                                class="timeline-status">

                                                ${escapeHTML(
                                                    event.estado
                                                )}
                                                ${
                                                    event.incident_category
                                                        ? ` · ${escapeHTML(event.incident_category)}`
                                                        : ""
                                                }
                                            </span>


                                            <span
                                                class="timeline-duration">

                                                ${escapeHTML(
                                                    event.duration
                                                )}

                                            </span>

                                        </div>


                                        <div
                                            class="timeline-time">

                                            ${escapeHTML(
                                                formatTimestamp(
                                                    event.start
                                                )
                                            )}

                                            ${
                                                event.end
                                                    ? " → " +
                                                      escapeHTML(
                                                          formatTimestamp(
                                                              event.end
                                                          )
                                                      )
                                                    : ""
                                            }

                                        </div>

                                        <div class="timeline-actor">
                                            ${escapeHTML(event.actor_label)}
                                        </div>


                                        ${
                                            event.observacion
                                                ? `

                                                    <div
                                                        class="timeline-observation">

                                                        ${escapeHTML(
                                                            event.observacion
                                                        )}

                                                    </div>

                                                `
                                                : ""
                                        }

                                    </div>

                                </div>

                            `;

                        }
                    ).join("")}

                </div>

            `
            : "";


    const reportButton =
        unit.estado === "Finalizado"
            ? `

                <button
                    class="report-button"
                    data-trip-id="${escapeHTML(
                        unit.viaje_id || ""
                    )}">

                    DESCARGAR INFORME

                </button>

              `
            : "";


    card.innerHTML = `

        <div class="unit-header">

            <div>

                <div class="unit-driver-id">
                    ${escapeHTML(driverId)}
                </div>

                <div class="unit-driver-name">
                    ${escapeHTML(conductor)}
                </div>

                <div class="unit-plate">
                    ${escapeHTML(plate)}
                </div>

            </div>


            <div class="status-badge ${statusClass}">

                ${escapeHTML(estado)}

            </div>

        </div>


        ${
            isStale
                ? `
                    <div class="report-age-alert" role="status">
                        ${
                            unit.has_report
                                ? `SIN ACTUALIZACIÓN · <span class="report-age-duration" data-start="${escapeHTML(lastActivity)}">${escapeHTML(staleDuration)}</span>`
                                : `SIN REPORTE OPERACIONAL · <span class="report-age-duration" data-start="${escapeHTML(lastActivity)}">${escapeHTML(staleDuration)}</span>`
                        }
                    </div>
                `
                : ""
        }


        <div class="unit-data">

            <div class="data-row">

                <span class="data-label">
                    VIAJE
                </span>

                <span class="data-value">
                    ${escapeHTML(unit.viaje_id || "--")}
                </span>

            </div>


            <div class="data-row">

                <span class="data-label">
                    EMPRESA
                </span>

                <span class="data-value">
                    ${escapeHTML(empresa)}
                </span>

            </div>


            <div class="data-row">

                <span class="data-label">
                    RUTA
                </span>

                <span class="data-value">
                    ${escapeHTML(ruta)}
                </span>

            </div>


            <div class="data-row">

                <span class="data-label">
                    ÚLTIMO REPORTE
                </span>

                <span class="data-value">
                    ${escapeHTML(timestamp)}
                </span>

            </div>


            <div class="data-row">

                <span class="data-label">
                    TIEMPO EN ESTADO
                </span>

                <span
                    class="data-value state-duration"
                    data-start="${escapeHTML(
                        unit.timestamp ||
                        unit.fecha_inicio ||
                        ""
                    )}">

                    ${escapeHTML(
                        liveDuration
                    )}

                </span>

            </div>


            <div class="data-row">

                <span class="data-label">
                    OBSERVACIÓN
                </span>

                <span class="data-value">
                    ${escapeHTML(observacion)}
                </span>

            </div>

            ${
                unit.incident_category
                    ? `
                        <div class="data-row">
                            <span class="data-label">CAUSA DEL INCIDENTE</span>
                            <span class="data-value">${escapeHTML(unit.incident_category)}</span>
                        </div>
                    `
                    : ""
            }

        </div>


        ${timelineHTML}


        ${mapsButton}


        ${reportButton}

    `;


    return card;

}


// =====================================================
// RENDER FILTRADO
// =====================================================

function renderFilteredUnits() {

    let filteredUnits;


    if (
        activeFilter === "all"
    ) {

        filteredUnits =
            currentUnits;

    }

    else {

        filteredUnits =
            currentUnits.filter(
                unit =>
                    unit.estado ===
                    activeFilter
            );

    }


    fleetContainer.innerHTML = "";


    if (
        filteredUnits.length === 0
    ) {

        fleetContainer.innerHTML = `

            <div class="empty-state">

                <div class="empty-code">
                    NO DATA
                </div>

                <div class="empty-title">
                    SIN UNIDADES EN ESTE ESTADO
                </div>

                <div class="empty-text">
                    No existen unidades que coincidan con el filtro seleccionado.
                </div>

            </div>

        `;

        return;

    }


    filteredUnits.forEach(
        unit => {

            fleetContainer.appendChild(
                createUnitCard(
                    unit
                )
            );

        }
    );

}


// =====================================================
// CONSTRUIR UNIDADES
// =====================================================

function buildUnits(
    trips,
    reports,
    conductorsById
) {

    const units = [];


    trips.forEach(
        trip => {

            // El tracto va ligado al conductor: un viaje sin conductor
            // (desasignado) no genera una tarjeta suelta solo con la patente.
            if (!trip.conductor_id) {
                return;
            }

            const tripReports =
                reports.filter(
                    report =>
                        report.viaje_id ===
                        trip.id
                );


            let latestReport =
                null;


            if (
                tripReports.length > 0
            ) {

                latestReport =
                    [...tripReports].sort(
                        (a, b) =>
                            new Date(b.timestamp) -
                            new Date(a.timestamp)
                    )[0];

            }


            const timeline =
                buildEventTimeline(
                    reports,
                    trip,
                    conductorsById
                );


            const currentState =
                trip.fecha_finalizacion
                    ? "Finalizado"
                    : (
                        latestReport?.estado ||
                        trip.estado ||
                        "En ruta"
                    );


            const currentTimestamp =
                latestReport?.timestamp ||
                trip.fecha_inicio ||
                trip.created_at;

            const conductorRecord =
                trip.conductor_id
                    ? conductorsById[trip.conductor_id]
                    : null;


            const unit = {

                viaje_id:
                    trip.id,

                patente:
                    normalizePlate(
                        trip.patente
                    ),

                conductor:
                    conductorRecord?.nombre ||
                    trip.conductor ||
                    null,

                driver_id:
                    conductorRecord?.driver_id ||
                    null,

                conductor_id:
                    trip.conductor_id ||
                    null,

                empresa:
                    trip.empresa ||
                    null,

                ruta:
                    trip.ruta ||
                    null,

                estado:
                    currentState,

                fecha_inicio:
                    trip.fecha_inicio ||
                    trip.created_at,

                fecha_finalizacion:
                    trip.fecha_finalizacion ||
                    null,

                timestamp:
                    currentTimestamp,

                latitud:
                    latestReport?.latitud ??
                    null,

                longitud:
                    latestReport?.longitud ??
                    null,

                precision_gps:
                    latestReport?.precision_gps ??
                    null,

                observacion:
                    latestReport?.observacion ??
                    null,

                incident_category:
                    latestReport?.incident_category ??
                    null,

                has_report:
                    Boolean(latestReport),

                timeline:
                    timeline

            };


            units.push(unit);

        }
    );


    return units;

}


// =====================================================
// FALLBACK LEGACY
// =====================================================

function buildLegacyUnits(
    reports,
    conductorsById
) {

    const latestByPlate = {};


    reports.forEach(
        report => {

            const plate =
                normalizePlate(
                    report.patente
                );


            if (!plate) {
                return;
            }

            // Sin conductor no hay unidad: el tracto nunca se muestra solo.
            if (!report.conductor_id && !report.conductor) {
                return;
            }


            const existing =
                latestByPlate[plate];


            if (
                !existing ||
                new Date(report.timestamp) >
                new Date(existing.timestamp)
            ) {

                const conductorRecord =
                    report.conductor_id
                        ? conductorsById[report.conductor_id]
                        : null;

                latestByPlate[plate] = {

                    viaje_id:
                        report.viaje_id ||
                        null,

                    driver_id:
                        conductorRecord?.driver_id ||
                        null,

                    patente:
                        plate,

                    conductor:
                        conductorRecord?.nombre ||
                        report.conductor ||
                        null,

                    empresa:
                        report.empresa ||
                        null,

                    ruta:
                        report.ruta ||
                        null,

                    estado:
                        report.estado ||
                        "En ruta",

                    fecha_inicio:
                        report.timestamp ||
                        report.created_at,

                    fecha_finalizacion:
                        report.estado ===
                        "Finalizado"
                            ? report.timestamp
                            : null,

                    timestamp:
                        report.timestamp ||
                        report.created_at,

                    latitud:
                        report.latitud ??
                        null,

                    longitud:
                        report.longitud ??
                        null,

                    precision_gps:
                        report.precision_gps ??
                        null,

                    observacion:
                        report.observacion ||
                        null,

                    incident_category:
                        report.incident_category ||
                        null,

                    has_report:
                        true,

                    timeline: []

                };

            }

        }
    );


    return Object.values(
        latestByPlate
    );

}


// =====================================================
// ORDENAR UNIDADES
// =====================================================

function sortUnits(
    units
) {

    return units.sort(
        (a, b) => {

            const priorityA =
                getStatusPriority(
                    a.estado
                );


            const priorityB =
                getStatusPriority(
                    b.estado
                );


            if (
                priorityA !==
                priorityB
            ) {

                return (
                    priorityA -
                    priorityB
                );

            }


            return (
                new Date(b.timestamp) -
                new Date(a.timestamp)
            );

        }
    );

}


// =====================================================
// CARGAR VIAJES
// =====================================================

async function loadTrips() {

    console.log(
        "FLEETOPS: cargando viajes..."
    );


    let tripsQuery =
        supabaseClient
            .from("viajes")
            .select(`
                id,
                patente,
                conductor,
                conductor_id,
                empresa,
                empresa_id,
                ruta,
                estado,
                fecha_inicio,
                fecha_finalizacion,
                created_at
            `);

    if (activeOrganizationId) {
        tripsQuery = tripsQuery.eq(
            "empresa_id",
            activeOrganizationId
        );
    }

    const {
        data,
        error
    } = await tripsQuery.order(
        "created_at",
        {
            ascending: false
        }
    );


    if (error) {

        throw new Error(
            "Error cargando viajes: " +
            error.message
        );

    }


    return data || [];

}


// =====================================================
// CARGAR REPORTES
// =====================================================

async function loadReports() {

    console.log(
        "FLEETOPS: cargando reportes..."
    );


    const {
        data,
        error
    } =
        await supabaseClient
            .from("reportes")
            .select(`
                id,
                viaje_id,
                conductor,
                conductor_id,
                actor_type,
                actor_conductor_id,
                actor_user_id,
                patente,
                empresa,
                ruta,
                estado,
                incident_category,
                latitud,
                longitud,
                precision_gps,
                observacion,
                timestamp,
                created_at
            `)
            .order(
                "timestamp",
                {
                    ascending: false
                }
            );


    if (error) {

        throw new Error(
            "Error cargando reportes: " +
            error.message
        );

    }


    return data || [];

}


// =====================================================
// CARGAR CONDUCTORES
// =====================================================

async function loadConductors() {

    console.log(
        "FLEETOPS: cargando conductores..."
    );

    const {
        data,
        error
    } =
        await supabaseClient
            .from("conductores")
            .select(`
                id,
                driver_id,
                nombre,
                telefono,
                rut,
                licencia,
                tipo_licencia,
                ciudad,
                patente_habitual,
                estado,
                tracto_id,
                licencia_vencimiento,
                fecha_registro
            `)
            .order(
                "fecha_registro",
                {
                    ascending: false
                }
            );

    if (error) {
        throw new Error(
            "Error cargando conductores: " +
            error.message
        );
    }

    return data || [];

}

async function loadDocumentData() {

    const [
        tractorsResponse,
        conductorDocumentsResponse,
        tractorDocumentsResponse
    ] =
        await Promise.all([
            supabaseClient
                .from("tractos")
                .select("id, patente"),
            supabaseClient
                .from("conductor_documentos")
                .select("id, conductor_id, tipo_documento, storage_path, nombre_archivo, estado_revision, fecha_carga"),
            supabaseClient
                .from("tracto_documentos")
                .select("id, tracto_id, tipo_documento, storage_path, nombre_archivo, estado_revision, fecha_carga")
        ]);

    const failedResponse = [
        tractorsResponse,
        conductorDocumentsResponse,
        tractorDocumentsResponse
    ].find(function (response) {
        return response.error;
    });

    if (failedResponse) {
        throw new Error(failedResponse.error.message);
    }

    return {
        tractors: tractorsResponse.data || [],
        conductorDocuments: conductorDocumentsResponse.data || [],
        tractorDocuments: tractorDocumentsResponse.data || []
    };

}


// =====================================================
// RENDER PRINCIPAL
// =====================================================

function renderDashboard(
    trips,
    reports,
    conductors,
    documentData
) {

    let units;

    const conductorsById =
        conductors.reduce(
            function (index, conductor) {
                index[conductor.id] = conductor;
                return index;
            },
            {}
        );


    if (
        trips.length > 0
    ) {

        console.log(
            "FLEETOPS: usando VIAJES + REPORTES."
        );


            units =
            buildUnits(
                trips.filter(function (trip) {
                    return !trip.fecha_finalizacion;
                }),
                reports,
                conductorsById
            );

    }

    else {

        console.log(
            "FLEETOPS: tabla VIAJES vacía. " +
            "Usando REPORTES como fallback."
        );


        units =
            buildLegacyUnits(
                reports,
                conductorsById
            );

    }


    units =
        sortUnits(
            units
        );


    currentUnits =
        units;

    currentConductors =
        conductors;

    currentTractos =
        documentData.tractors;

    currentConductorDocuments =
        documentData.conductorDocuments;

    currentTractoDocuments =
        documentData.tractorDocuments;

    renderConductors(
        conductors
    );


    updateSummary(
        units
    );


    updateFilterCounts(
        units
    );


    renderFilteredUnits();


    if (lastUpdate) {

        lastUpdate.innerText =
            formatTimestamp(
                new Date().toISOString()
            );

    }

}


// =====================================================
// DASHBOARD
// =====================================================

async function loadDashboard() {

    if (!dashboardAccessValid || !activeOrganizationId) {
        return;
    }

    console.log(
        "FLEETOPS: actualizando dashboard..."
    );


    try {

        const [
            trips,
            reports
        ] =
            await Promise.all(
                [
                    loadTrips(),
                    loadReports()
                ]
            );

        const tripIds = new Set(
            trips.map(trip => trip.id)
        );

        const organizationReports = reports.filter(
            report => tripIds.has(report.viaje_id)
        );

        let conductors = [];

        try {
            conductors =
                await loadConductors();
        }
        catch (conductorError) {
            console.error(
                "FLEETOPS: error cargando conductores",
                conductorError
            );
        }

        let documentData = {
            tractors: [],
            conductorDocuments: [],
            tractorDocuments: []
        };

        try {
            documentData =
                await loadDocumentData();
        }
        catch (documentError) {
            console.error(
                "FLEETOPS: error cargando documentos",
                documentError
            );
        }


        setConnectionStatus(
            true
        );


        renderDashboard(
            trips,
            organizationReports,
            conductors,
            documentData
        );

    }

    catch (error) {

        console.error(
            "FLEETOPS DATABASE ERROR:",
            error
        );


        setConnectionStatus(
            false
        );


        fleetContainer.innerHTML = `

            <div class="empty-state">

                <div class="empty-code">
                    DATABASE ERROR
                </div>

                <div class="empty-title">
                    ERROR AL CARGAR DATOS
                </div>

                <div class="empty-text">
                    No fue posible obtener los datos operacionales desde Supabase.
                </div>

            </div>

        `;

    }

}


// =====================================================
// TIEMPOS EN TIEMPO REAL
// =====================================================

function updateLiveDurations() {

    document
        .querySelectorAll(
            ".state-duration, .report-age-duration"
        )
        .forEach(
            element => {

                const start =
                    element.dataset.start;


                if (!start) {
                    return;
                }


                element.innerText =
                    formatLiveDuration(
                        start
                    );

            }
        );

}


// =====================================================
// FILTROS
// =====================================================

document
    .querySelectorAll(
        ".filter-button"
    )
    .forEach(
        button => {

            button.addEventListener(
                "click",
                function () {

                    document
                        .querySelectorAll(
                            ".filter-button"
                        )
                        .forEach(
                            btn => {

                                btn.classList.remove(
                                    "active"
                                );

                            }
                        );


                    this.classList.add(
                        "active"
                    );


                    activeFilter =
                        this.dataset.filter;


                    renderFilteredUnits();

                }
            );

        }
    );



// =====================================================
// INFORME OPERACIONAL
// =====================================================

function downloadTripReport(tripId) {

    const unit =
        currentUnits.find(
            item =>
                item.viaje_id === tripId
        );

    if (!unit) {

        console.error(
            "FLEETOPS: viaje no encontrado:",
            tripId
        );

        return;
    }


    const timeline =
        unit.timeline || [];

    function formatTimestampForExport(timestamp) {
        if (!timestamp) {
            return "";
        }

        const date = new Date(timestamp);
        return Number.isNaN(date.getTime())
            ? ""
            : date.toISOString();
    }


    const rows = [];


    rows.push([
        "PRÆTOR FleetOps - INFORME OPERACIONAL"
    ]);

    rows.push([]);

    rows.push([
        "VIAJE ID",
        unit.viaje_id || ""
    ]);

    rows.push([
        "PATENTE",
        unit.patente || ""
    ]);

    rows.push([
        "CONDUCTOR",
        unit.conductor || ""
    ]);

    rows.push([
        "DRIVER ID",
        unit.driver_id || ""
    ]);

    rows.push([
        "EMPRESA",
        unit.empresa || ""
    ]);

    rows.push([
        "RUTA",
        unit.ruta || ""
    ]);

    rows.push([]);

    rows.push([
        "INICIO VIAJE",
        unit.fecha_inicio
            ? formatTimestampForExport(unit.fecha_inicio)
            : ""
    ]);

    rows.push([
        "FINALIZACIÓN VIAJE",
        unit.fecha_finalizacion
            ? formatTimestampForExport(unit.fecha_finalizacion)
            : ""
    ]);

    rows.push([
        "DURACIÓN TOTAL",
        unit.fecha_inicio &&
        unit.fecha_finalizacion
            ? formatDurationCompact(
                unit.fecha_inicio,
                unit.fecha_finalizacion
            )
            : "--"
    ]);

    rows.push([]);

    rows.push([
        "ESTADO",
        "ACTOR",
        "CAUSA DEL INCIDENTE",
        "INICIO",
        "FIN",
        "DURACIÓN",
        "LATITUD",
        "LONGITUD",
        "OBSERVACIÓN"
    ]);


    timeline.forEach(
        event => {

            rows.push([
                event.estado || "",
                event.actor_label || "IDENTIDAD NO VERIFICADA",
                event.incident_category || "",

                event.start
                    ? formatTimestampForExport(
                        event.start
                    )
                    : "",

                event.end
                    ? formatTimestampForExport(
                        event.end
                    )
                    : "",

                event.duration || "",

                event.latitud ??
                    "",

                event.longitud ??
                    "",

                event.observacion || ""

            ]);

        }
    );


    function escapeCSV(value) {

        const stringValue =
            String(value ?? "");

        if (
            /[",\r\n]/.test(
                stringValue
            )
        ) {

            return (
                '"' +
                stringValue.replace(
                    /"/g,
                    '""'
                ) +
                '"'
            );

        }

        return stringValue;

    }


    const csv =
        rows
            .map(
                row =>
                    row
                        .map(
                            escapeCSV
                        )
                        .join(",")
            )
            .join("\r\n");


    const blob =
        new Blob(
            [
                "\uFEFF",
                csv
            ],
            {
                type:
                    "text/csv;charset=utf-8"
            }
        );


    const url =
        URL.createObjectURL(
            blob
        );


    const link =
        document.createElement(
            "a"
        );


    link.href =
        url;


    link.download =
        `FleetOps_${unit.patente || "viaje"}_${tripId}.csv`;


    document.body.appendChild(
        link
    );


    link.click();


    document.body.removeChild(
        link
    );


    setTimeout(
        () => {

            URL.revokeObjectURL(
                url
            );

        },
        1000
    );


    console.log(
        "FLEETOPS: informe descargado:",
        link.download
    );

}

// =====================================================
// EVENTO DESCARGA INFORME
// =====================================================

document.addEventListener(
    "click",
    function (event) {

        const button =
            event.target.closest(
                ".report-button"
            );


        if (!button) {
            return;
        }


        event.preventDefault();


        const tripId =
            button.getAttribute(
                "data-trip-id"
            );


        if (!tripId) {

            console.error(
                "FLEETOPS: el botón no contiene viaje_id."
            );

            return;
        }


        downloadTripReport(
            tripId
        );

    }
);


// =====================================================
// INICIALIZACIÓN
// =====================================================

console.log(
    "PRÆTOR FleetOps Dashboard iniciado."
);


initializeOperatorSession()
    .then(function (authenticated) {
        if (authenticated) {
            loadDashboard();
            dashboardPollingId = setInterval(
                async function () {
                    if (await initializeOperatorSession()) {
                        loadDashboard();
                    }
                },
                10000
            );
        }
    });

// =====================================================
// ACTUALIZACIÓN VISUAL DE TIEMPOS
// =====================================================

setInterval(
    updateLiveDurations,
    1000
);
