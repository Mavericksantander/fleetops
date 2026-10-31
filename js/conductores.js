const routePool =
    document.getElementById("routePool");

const completedPool =
    document.getElementById("completedPool");

const poolCount =
    document.getElementById("poolCount");

const operationalCount =
    document.getElementById("operationalCount");

const connectionIndicator =
    document.getElementById("connectionIndicator");

const connectionText =
    document.getElementById("connectionText");

const assignmentModal =
    document.getElementById("assignmentModal");

const assignmentForm =
    document.getElementById("assignmentForm");

const assignmentError =
    document.getElementById("assignmentError");

const assignmentDriver =
    document.getElementById("assignmentDriver");

const assignmentConductorId =
    document.getElementById("assignmentConductorId");

const assignmentRouteName =
    document.getElementById("assignmentRouteName");

const assignmentRoute =
    document.getElementById("assignmentRoute");

const assignmentCompany =
    document.getElementById("assignmentCompany");

const driverProfileModal =
    document.getElementById("driverProfileModal");

const driverProfileDriver =
    document.getElementById("driverProfileDriver");

const driverProfileContent =
    document.getElementById("driverProfileContent");

const closeDriverProfileButton =
    document.getElementById("closeDriverProfile");

let currentConductors = [];
let currentPendingConductors = [];
let currentTrips = [];
let currentRoutes = [];
let activeOrganizationId = null;
let activeOrganization = null;
let canManageDrivers = false;
let canAssignOperations = false;
let returnedCompletedTripIds = new Set();

function getReturnedCompletedTripStorageKey() {
    return `fleetops.returned_completed_trips.${activeOrganizationId}`;
}

function loadReturnedCompletedTripIds() {
    try {
        const stored = JSON.parse(
            localStorage.getItem(getReturnedCompletedTripStorageKey()) || "[]"
        );
        returnedCompletedTripIds = new Set(
            Array.isArray(stored) ? stored : []
        );
    }
    catch (error) {
        console.warn("No fue posible cargar conductores devueltos a disponibles:", error);
        returnedCompletedTripIds = new Set();
    }
}

function saveReturnedCompletedTripIds() {
    localStorage.setItem(
        getReturnedCompletedTripStorageKey(),
        JSON.stringify([...returnedCompletedTripIds])
    );
}

function escapeHTML(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function setConnectionStatus(connected) {
    connectionIndicator.classList.toggle("connected", connected);
    connectionIndicator.classList.toggle("disconnected", !connected);
    connectionText.innerText = connected
        ? "CONNECTED"
        : "DATABASE ERROR";
}

async function initializeOperatorSession() {

    const context = await resolveOrganizationContext();

    if (!context.session || !context.activeOrganization) {
        window.location.replace(
            `login.html?next=${encodeURIComponent(window.location.pathname)}`
        );
        return false;
    }

    activeOrganizationId = context.activeOrganization.id;
    activeOrganization = context.activeOrganization;
    loadReturnedCompletedTripIds();
    const { data: membership, error } = await supabaseClient
        .from("organization_members")
        .select("role")
        .eq("organization_id", activeOrganizationId)
        .eq("user_id", context.session.user.id)
        .maybeSingle();
    if (error) {
        throw error;
    }
    if (membership?.role === "customer") {
        window.location.replace("customer-dashboard.html");
        return false;
    }
    canManageDrivers = ["owner", "admin"].includes(membership?.role);
    // INSERT viajes y finalizar_viaje admiten owner, admin y operator.
    canAssignOperations = ["owner", "admin", "operator"].includes(membership?.role);

    return true;

}

function getAssignmentByDriver(trips) {
    const assignments = {};

    trips.forEach(function (trip) {
        if (!trip.conductor_id || trip.fecha_finalizacion) {
            return;
        }

        if (!assignments[trip.conductor_id]) {
            assignments[trip.conductor_id] = trip;
        }
    });

    return assignments;
}

function normalizePlate(value) {
    return String(value || "")
        .replace(/[^a-zA-Z0-9]/g, "")
        .toUpperCase();
}

function openAssignment(conductor) {

    if (!canAssignOperations) {
        return;
    }

    const activeAssignment =
        getAssignmentByDriver(currentTrips)[conductor.id];

    if (activeAssignment) {
        alert("Este conductor ya tiene un viaje activo.");
        return;
    }

    assignmentConductorId.value = conductor.id;
    assignmentDriver.innerText =
        `${conductor.driver_id} · ${conductor.nombre}`;
    assignmentForm.reset();
    assignmentConductorId.value = conductor.id;
    assignmentError.innerText = "";
    assignmentModal.hidden = false;

}

function closeAssignment() {
    assignmentModal.hidden = true;
}

function renderEmpty(title, text) {
    routePool.innerHTML = `
        <div class="empty-state">
            <div class="empty-code">NO DATA</div>
            <div class="empty-title">${escapeHTML(title)}</div>
            <div class="empty-text">${escapeHTML(text)}</div>
        </div>
    `;
}

function selectLinkedConductors(relationships, status) {
    return (relationships || [])
        .filter(function (relationship) {
            return relationship.status === status &&
                relationship.organization_id === activeOrganizationId &&
                relationship.conductor;
        })
        .map(function (relationship) {
            return relationship.conductor;
        });
}

function getOrganizationConductorsById() {
    // Solo conductores vinculados a la organización activa (organization_drivers
    // ya viene filtrado por activeOrganizationId en loadDriverPool).
    const index = {};
    (currentConductors || []).forEach(function (conductor) {
        if (conductor && conductor.id) {
            index[conductor.id] = conductor;
        }
    });
    return index;
}

function getCompletedTripsForActiveOrganization(trips) {
    const conductorsById = getOrganizationConductorsById();

    // El tracto va ligado al conductor: un viaje sin conductor (o con un
    // conductor que no pertenece a la org activa) no genera fila.
    return trips
        .filter(function (trip) {
            return Boolean(trip.fecha_finalizacion) &&
                trip.empresa_id === activeOrganizationId &&
                Boolean(trip.conductor_id) &&
                Boolean(conductorsById[trip.conductor_id]) &&
                !returnedCompletedTripIds.has(trip.id);
        })
        .map(function (trip) {
            return { trip, conductor: conductorsById[trip.conductor_id] };
        });
}

function renderCompletedPools(trips) {

    const completedByRoute = {};

    getCompletedTripsForActiveOrganization(trips)
        .forEach(function (entry) {
            const routeName = entry.trip.ruta || "SIN RUTA ASOCIADA";

            if (!completedByRoute[routeName]) {
                completedByRoute[routeName] = [];
            }

            completedByRoute[routeName].push(entry);
        });

    if (Object.keys(completedByRoute).length === 0) {
        completedPool.innerHTML = `
            <div class="empty-state">
                <div class="empty-title">SIN VIAJES FINALIZADOS</div>
                <div class="empty-text">Los conductores aparecerán aquí al finalizar una operación.</div>
            </div>
        `;
        return;
    }

    completedPool.innerHTML = Object.entries(completedByRoute).map(function ([routeName, entries]) {
        return `
            <section class="route-group completed-route-group">
                <div class="route-group-header">
                    <div class="route-name">${escapeHTML(routeName)}</div>
                    <div class="route-count">${entries.length} FINALIZADO${entries.length === 1 ? "" : "S"}</div>
                </div>
                <div class="route-driver-list">
                    ${entries.map(function ({ trip, conductor }) {
                        // Primero el tracto que hizo el viaje; si no existe, el actual del conductor.
                        const tractoPatente =
                            trip.patente ||
                            conductor.tracto?.patente ||
                            conductor.patente_habitual ||
                            "SIN PATENTE";
                        return `
                            <article class="route-driver" data-trip-id="${escapeHTML(trip.id)}">
                                <div class="route-driver-top">
                                    <div>
                                        <div class="route-driver-id">${escapeHTML(conductor.driver_id || "")}</div>
                                        <div class="route-driver-name">${escapeHTML(conductor.nombre || trip.conductor || "")}</div>
                                    </div>
                                    <div>
                                        <div class="route-driver-plate">
                                            <span class="route-driver-plate-label">EQUIPO / PATENTE</span>
                                            ${escapeHTML(tractoPatente)}
                                        </div>
                                        <div class="route-driver-state">FINALIZADO</div>
                                    </div>
                                </div>
                                <div class="route-driver-meta">VIAJE ${escapeHTML(trip.id)} · ${escapeHTML(trip.empresa || "SIN EMPRESA")}</div>
                                ${canAssignOperations ? `<button type="button" class="assignment-button reassign-button" data-conductor-id="${escapeHTML(conductor.id)}">REASIGNAR</button>` : ""}
                                ${routeName === "SIN RUTA ASOCIADA" ? `<button type="button" class="assignment-button return-available-button" data-trip-id="${escapeHTML(trip.id)}">DEVOLVER A DISPONIBLES</button>` : ""}
                            </article>
                        `;
                    }).join("")}
                </div>
            </section>
        `;
    }).join("");

}

function returnCompletedTripToAvailable(tripId) {
    // Solo acepta un viaje finalizado de la org activa con conductor vinculado;
    // un id de otra organización (p. ej. un data-trip-id manipulado) se ignora.
    const allowed = getCompletedTripsForActiveOrganization(currentTrips || [])
        .some(function (entry) {
            return entry.trip.id === tripId;
        });

    if (!allowed) {
        return false;
    }

    returnedCompletedTripIds.add(tripId);
    saveReturnedCompletedTripIds();
    renderCompletedPools(currentTrips);
    return true;
}

async function getDocumentSignedUrl(storagePath) {
    if (!storagePath) {
        return null;
    }

    const { data, error } = await supabaseClient.storage
        .from("fleetops-documents")
        .createSignedUrl(storagePath, 3600);

    if (error) {
        console.error("FLEETOPS DOCUMENT URL ERROR:", error);
        return null;
    }

    return data?.signedUrl || null;
}

async function openDriverProfile(driverId) {

    const cachedConductor =
        currentConductors.concat(currentPendingConductors).find(function (item) {
            return item.id === driverId;
        });

    if (!cachedConductor) {
        return;
    }

    const { data: conductor, error: conductorError } =
        await supabaseClient
            .from("conductores")
            .select("id, driver_id, rut, nombre, telefono, tipo_licencia, ciudad, patente_habitual, estado, tracto_id, licencia, licencia_vencimiento")
            .eq("id", driverId)
            .maybeSingle();

    if (conductorError) {
        throw conductorError;
    }

    if (!conductor) {
        return;
    }

    let equipment = null;

    if (conductor.tracto_id) {
        const { data: tracto, error: tractoError } =
            await supabaseClient
                .from("tractos")
                .select("id, patente, estado")
                .eq("id", conductor.tracto_id)
                .maybeSingle();

        if (tractoError) {
            throw tractoError;
        }

        equipment = tracto;
    }

    const [conductorDocumentsResponse, tractoDocumentsResponse] =
        await Promise.all([
            supabaseClient
                .from("conductor_documentos")
                .select("id, conductor_id, tipo_documento, storage_path, nombre_archivo, mime_type, tamano_bytes, estado_revision, fecha_carga")
                .eq("conductor_id", driverId)
                .order("fecha_carga", { ascending: false }),
            equipment
                ? supabaseClient
                    .from("tracto_documentos")
                    .select("id, tracto_id, tipo_documento, storage_path, nombre_archivo, mime_type, tamano_bytes, estado_revision, fecha_carga")
                    .eq("tracto_id", equipment.id)
                    .order("fecha_carga", { ascending: false })
                : Promise.resolve({ data: [], error: null })
        ]);

    if (conductorDocumentsResponse.error) {
        throw conductorDocumentsResponse.error;
    }

    if (tractoDocumentsResponse.error) {
        throw tractoDocumentsResponse.error;
    }

    const conductorDocuments = conductorDocumentsResponse.data || [];
    const equipmentDocuments = tractoDocumentsResponse.data || [];

    const selfieDocument =
        conductorDocuments.find(function (document) {
            return document.tipo_documento === "selfie";
        });

    const selfieUrl =
        selfieDocument
            ? await getDocumentSignedUrl(selfieDocument.storage_path)
            : null;

    const driverDocuments =
        await Promise.all(
            conductorDocuments
                .filter(function (document) {
                    return document.tipo_documento !== "selfie";
                })
                .map(async function (document) {
                    return {
                        ...document,
                        signedUrl: await getDocumentSignedUrl(document.storage_path)
                    };
                })
        );

    const equipmentDocumentUrls =
        await Promise.all(
            equipmentDocuments.map(async function (document) {
                return {
                    ...document,
                    signedUrl: await getDocumentSignedUrl(document.storage_path)
                };
            })
        );

    driverProfileDriver.innerHTML = `
        <div style="display:flex; flex-direction:column; align-items:center; gap:12px;">
            ${
                selfieUrl
                    ? `
                        <img
                            src="${escapeHTML(selfieUrl)}"
                            alt="Foto de ${escapeHTML(conductor.nombre || "conductor")}"
                            style="
                                width:96px;
                                height:96px;
                                border-radius:50%;
                                object-fit:cover;
                                border:2px solid rgba(255,255,255,0.15);
                            "
                        >
                    `
                    : `
                        <div
                            style="
                                width:96px;
                                height:96px;
                                border-radius:50%;
                                display:flex;
                                align-items:center;
                                justify-content:center;
                                background:#111;
                                color:#777;
                                font-size:12px;
                            "
                        >
                            SIN FOTO
                        </div>
                    `
            }

            <div>
                ${escapeHTML(conductor.driver_id)} · ${escapeHTML(conductor.nombre)}
            </div>
        </div>
    `;

    function renderDocumentCard(document) {

        const label =
            document.tipo_documento === "licencia_frente"
                ? "LICENCIA · FRENTE"
                : document.tipo_documento === "licencia_reverso"
                    ? "LICENCIA · REVERSO"
                    : document.tipo_documento === "permiso_circulacion"
                        ? "PERMISO DE CIRCULACIÓN"
                        : document.tipo_documento === "soap"
                            ? "SOAP"
                            : document.tipo_documento === "revision_tecnica"
                                ? "REVISIÓN TÉCNICA"
                                : document.tipo_documento === "padron_vehicular"
                                    ? "PADRÓN VEHICULAR"
                                    : String(document.tipo_documento || "DOCUMENTO").toUpperCase();

        if (!document.signedUrl) {
            return `
                <div class="driver-document-card">
                    <div class="driver-document-label">
                        ${escapeHTML(label)}
                    </div>
                    <div class="driver-document-unavailable">
                        NO DISPONIBLE
                    </div>
                </div>
            `;
        }

        const mimeType =
            String(document.mime_type || "").toLowerCase();

        const isImage =
            mimeType.startsWith("image/");

        if (isImage) {
            return `
                <div class="driver-document-card">
                    <div class="driver-document-label">
                        ${escapeHTML(label)}
                    </div>

                    <a
                        href="${escapeHTML(document.signedUrl)}"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="driver-document-link"
                    >
                        <img
                            src="${escapeHTML(document.signedUrl)}"
                            alt="${escapeHTML(label)}"
                            class="driver-document-image"
                        >
                    </a>

                    <div class="driver-document-filename">
                        ${escapeHTML(document.nombre_archivo || "ARCHIVO")}
                    </div>
                </div>
            `;
        }

        return `
            <div class="driver-document-card">
                <div class="driver-document-label">
                    ${escapeHTML(label)}
                </div>

                <a
                    href="${escapeHTML(document.signedUrl)}"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="driver-document-link"
                    style="display:flex; align-items:center; justify-content:center; min-height:120px; text-decoration:none;"
                >
                    <span style="font-size:14px; font-weight:600;">
                        ABRIR DOCUMENTO
                    </span>
                </a>

                <div class="driver-document-filename">
                    ${escapeHTML(document.nombre_archivo || "ARCHIVO")}
                </div>
            </div>
        `;
    }

    driverProfileContent.innerHTML = `
        <section class="profile-section">
            <div class="profile-section-title">IDENTIDAD</div>

            <div class="profile-grid">
                <div class="data-row">
                    <span class="data-label">NOMBRE</span>
                    <span class="data-value">${escapeHTML(conductor.nombre || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">TELÉFONO</span>
                    <span class="data-value">${escapeHTML(conductor.telefono || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">RUT</span>
                    <span class="data-value">${escapeHTML(conductor.rut || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">CIUDAD</span>
                    <span class="data-value">${escapeHTML(conductor.ciudad || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">LICENCIA</span>
                    <span class="data-value">${escapeHTML(conductor.tipo_licencia || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">NÚMERO LICENCIA</span>
                    <span class="data-value">${escapeHTML(conductor.licencia || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">VENCIMIENTO</span>
                    <span class="data-value">${escapeHTML(conductor.licencia_vencimiento || "--")}</span>
                </div>

                <div class="data-row">
                    <span class="data-label">ESTADO</span>
                    <span class="data-value">${escapeHTML(conductor.estado || "--")}</span>
                </div>
            </div>
        </section>

        <section class="profile-section">
            <div class="profile-section-title">EQUIPO</div>

            <div class="profile-grid">
                <div class="data-row">
                    <span class="data-label">PATENTE</span>
                    <span class="data-value">
                        ${escapeHTML(equipment?.patente || conductor.patente_habitual || "--")}
                    </span>
                </div>

                <div class="data-row">
                    <span class="data-label">ESTADO</span>
                    <span class="data-value">
                        ${escapeHTML(equipment?.estado || "--")}
                    </span>
                </div>
            </div>
        </section>

        <section class="profile-section">
            <div class="profile-section-title">DOCUMENTACIÓN DEL CONDUCTOR</div>

            <div class="driver-documents">
                ${
                    driverDocuments.length
                        ? driverDocuments.map(renderDocumentCard).join("")
                        : `
                            <div class="driver-document-unavailable">
                                SIN DOCUMENTOS
                            </div>
                        `
                }
            </div>
        </section>

        <section class="profile-section">
            <div class="profile-section-title">DOCUMENTACIÓN DEL EQUIPO</div>

            <div class="driver-documents">
                ${
                    equipmentDocumentUrls.length
                        ? equipmentDocumentUrls.map(renderDocumentCard).join("")
                        : `
                            <div class="driver-document-unavailable">
                                SIN DOCUMENTOS
                            </div>
                        `
                }
            </div>
        </section>
    `;

    driverProfileModal.hidden = false;
}

function renderDriverCards(drivers, includeAssignmentButtons) {
    return drivers.map(function ({ conductor, assignment }) {
        const state =
            assignment?.estado ||
            (conductor.estado === "Disponible"
                ? "Pendiente de asignación"
                : conductor.estado) ||
            "SIN ESTADO";

        return `
            <article class="route-driver">
                <div class="route-driver-top">
                    <div>
                        <div class="route-driver-id">${escapeHTML(conductor.driver_id)}</div>
                        <div class="route-driver-name">${escapeHTML(conductor.nombre)}</div>
                    </div>
                    <div>
                        <div class="route-driver-plate">
                            <span class="route-driver-plate-label">EQUIPO / PATENTE</span>
                            ${escapeHTML(conductor.tracto?.patente || conductor.patente_habitual || assignment?.patente || "SIN PATENTE")}
                        </div>
                        <div class="route-driver-state">${escapeHTML(state)}</div>
                    </div>
                </div>
                <div class="route-driver-meta">
                    ${escapeHTML(conductor.ciudad || "SIN CIUDAD")} · ${escapeHTML(conductor.tipo_licencia || "SIN LICENCIA")} · ${escapeHTML(conductor.telefono || "SIN TELEFONO")}
                </div>
                <button type="button" class="profile-button" data-conductor-id="${escapeHTML(conductor.id)}">VER PERFIL</button>
                ${includeAssignmentButtons
                    ? (canAssignOperations
                        ? `<button type="button" class="assignment-button" data-conductor-id="${escapeHTML(conductor.id)}">ASIGNAR OPERACIÓN</button>`
                        : "")
                    : `<button type="button" class="assignment-button" disabled>VIAJE ACTIVO</button>${canAssignOperations ? `<button type="button" class="assignment-button remove-route-button" data-trip-id="${escapeHTML(assignment.id)}">RETIRAR DE RUTA</button>` : ""}`}
            </article>
        `;
    }).join("");
}

function renderGroupedDrivers(groups) {
    return Object.entries(groups).map(function ([routeName, drivers]) {
        return `
            <section class="route-group">
                <div class="route-group-header">
                    <div class="route-name">${escapeHTML(routeName)}</div>
                    <div class="route-count">${drivers.length} CONDUCTOR${drivers.length === 1 ? "" : "ES"}</div>
                </div>
                <div class="route-driver-list">
                    ${renderDriverCards(drivers, false)}
                </div>
            </section>
        `;
    }).join("");
}

function renderPools(relationships, trips, routes) {
    const conductors = relationships
        .filter(function (relationship) {
            return relationship.status === "ACTIVE" && relationship.conductor;
        })
        .map(function (relationship) {
            return relationship.conductor;
        });
    const pending = relationships.filter(function (relationship) {
        return relationship.status === "PENDING" && relationship.conductor;
    });
    const activeTrips = trips.filter(function (trip) {
        return Boolean(trip.conductor_id) &&
            !trip.fecha_finalizacion;
    });
    const operationalByDriver = getAssignmentByDriver(activeTrips);
    const freeDrivers = conductors
        .filter(function (conductor) {
            return !operationalByDriver[conductor.id];
        })
        .map(function (conductor) {
            return { conductor, assignment: null };
        });
    const operationalDrivers = conductors
        .filter(function (conductor) {
            return Boolean(operationalByDriver[conductor.id]);
        })
        .map(function (conductor) {
            return {
                conductor,
                assignment: operationalByDriver[conductor.id]
            };
        });
    const operationalGroups = {};

    operationalDrivers.forEach(function (driver) {
        const route = currentRoutes.find(function (item) {
            return item.id === driver.assignment.route_id;
        });
        const routeName = route?.name || driver.assignment.ruta || "SIN RUTA ASOCIADA";
        if (!operationalGroups[routeName]) {
            operationalGroups[routeName] = [];
        }
        operationalGroups[routeName].push(driver);
    });

    // Solo vínculos aprobados/activos (status ACTIVE) cuentan como conductores
    // de la organización. Los PENDING se guardan aparte (solo para VER PERFIL).
    currentConductors = selectLinkedConductors(relationships, "ACTIVE");
    currentPendingConductors = selectLinkedConductors(relationships, "PENDING");
    currentTrips = trips;
    currentRoutes = routes;
    poolCount.innerText = conductors.length;
    operationalCount.innerText = operationalDrivers.length;

    assignmentRoute.innerHTML = `<option value="">SIN RUTA ASIGNADA</option>` + routes
        .filter(function (route) {
            return route.organization_id === activeOrganizationId && route.active;
        })
        .map(function (route) {
            return `<option value="${escapeHTML(route.id)}">${escapeHTML(route.name)}</option>`;
        }).join("");

    const poolMarkup = freeDrivers.length
        ? `<div class="route-group"><div class="route-group-header"><div class="route-name">DISPONIBLES</div><div class="route-count">${freeDrivers.length} CONDUCTOR${freeDrivers.length === 1 ? "" : "ES"}</div></div><div class="route-driver-list">${renderDriverCards(freeDrivers, true)}</div></div>`
        : `<div class="empty-state"><div class="empty-title">SIN CONDUCTORES DISPONIBLES</div><div class="empty-text">Agrega o libera conductores de esta organización.</div></div>`;
    const operationalMarkup = operationalDrivers.length
        ? renderGroupedDrivers(operationalGroups)
        : `<div class="empty-state"><div class="empty-title">SIN OPERATIVOS</div><div class="empty-text">No hay conductores activos en esta organización.</div></div>`;

    routePool.innerHTML = `
        <section class="pool-zone">
            <div class="pool-zone-header"><div class="pool-zone-title">MIS CONDUCTORES</div><div class="pool-zone-description">Conductores ACTIVE de ${escapeHTML(activeOrganization.name || "la organización activa")}.</div>${canManageDrivers ? '<button type="button" class="assignment-button invite-driver-button">INVITAR CONDUCTOR</button>' : ""}</div>
            <div class="route-pool">${poolMarkup}</div>
        </section>
        <section class="pool-zone">
            <div class="pool-zone-header"><div class="pool-zone-title">SOLICITUDES PENDIENTES</div></div>
            <div class="route-pool">${renderPendingDrivers(pending)}</div>
        </section>
        <section class="pool-zone">
            <div class="pool-zone-header"><div class="pool-zone-title">OPERATIVOS</div><div class="pool-zone-description">Conductores actualmente asignados a ${escapeHTML(activeOrganization.name || "la organización activa")}.</div></div>
            <div class="route-pool">${operationalMarkup}</div>
        </section>
    `;

    renderCompletedPools(trips);
}

function renderPendingDrivers(pending) {
    if (!pending.length) {
        return `<div class="empty-state"><div class="empty-title">SIN SOLICITUDES PENDIENTES</div></div>`;
    }
    return pending.map(function (relationship) {
        const conductor = relationship.conductor;
        return `<article class="route-driver">
            <div class="route-driver-top">
                <div><div class="route-driver-id">${escapeHTML(conductor.driver_id)}</div><div class="route-driver-name">${escapeHTML(conductor.nombre)}</div></div>
                <div class="route-driver-state">PENDING</div>
            </div>
            <div class="route-driver-meta">${escapeHTML(conductor.rut || "SIN RUT")} · ${escapeHTML(conductor.telefono || "SIN TELÉFONO")}</div>
            <button type="button" class="profile-button" data-conductor-id="${escapeHTML(conductor.id)}">VER PERFIL</button>
            ${canManageDrivers ? `<button type="button" class="assignment-button approve-driver-button" data-conductor-id="${escapeHTML(conductor.id)}">APROBAR</button>
            <button type="button" class="assignment-button reject-driver-button" data-conductor-id="${escapeHTML(conductor.id)}">RECHAZAR</button>` : ""}
        </article>`;
    }).join("");
}

async function createDriverInvite() {
    if (!canManageDrivers) {
        return;
    }

    const { data, error } = await supabaseClient.rpc(
        "create_organization_driver_invite",
        { p_organization_id: activeOrganizationId }
    );

    if (error || !data?.[0]?.invite_token) {
        alert(error?.message || "No fue posible generar la invitación.");
        return;
    }

    const link =
        `${window.location.origin}${window.location.pathname.replace(/\/[^/]*$/, "/")}driver.html?invite=${encodeURIComponent(data[0].invite_token)}`;

    const dialog = document.createElement("div");
    dialog.className = "assignment-modal";
    dialog.innerHTML = `
        <div class="assignment-dialog driver-invite-dialog" role="dialog" aria-modal="true" aria-labelledby="driverInviteTitle" aria-describedby="driverInviteDescription">
            <div class="driver-invite-header">
                <div class="driver-invite-heading">
                    <span class="driver-invite-icon" aria-hidden="true">✓</span>
                    <div>
                        <div class="driver-invite-eyebrow">ACCESO DE CONDUCTOR</div>
                        <div class="section-title" id="driverInviteTitle">INVITACIÓN GENERADA</div>
                    </div>
                </div>
                <button type="button" class="assignment-close" data-close-invite aria-label="Cerrar">×</button>
            </div>
            <p class="driver-invite-description" id="driverInviteDescription">Comparte este enlace con el conductor para completar su registro y unirse a la organización.</p>
            <label class="driver-invite-label" for="driverInviteUrl">ENLACE DE INVITACIÓN</label>
            <input class="driver-invite-url" id="driverInviteUrl" type="text" readonly value="${escapeHTML(link)}">
            <button type="button" class="assignment-submit driver-invite-copy" data-copy-invite>COPIAR ENLACE</button>
        </div>
    `;
    document.body.appendChild(dialog);
    dialog.hidden = false;

    dialog.querySelector("[data-copy-invite]").addEventListener("click", async function () {
        if (!navigator.clipboard?.writeText) {
            window.prompt("Copia este enlace de invitación:", link);
            return;
        }
        try {
            await navigator.clipboard.writeText(link);
            this.innerText = "ENLACE COPIADO";
        }
        catch (clipboardError) {
            console.warn("No fue posible copiar la invitación:", clipboardError);
            window.prompt("Copia este enlace de invitación:", link);
        }
    });
    dialog.querySelector("[data-close-invite]").addEventListener("click", function () {
        dialog.remove();
    });
}

async function loadDriverPool() {
    const [
        driversResponse,
        tripsResponse,
        routesResponse
    ] = await Promise.all([
        supabaseClient
            .from("organization_drivers")
            .select("organization_id, conductor_id, status, conductor:conductores(id, driver_id, rut, nombre, telefono, tipo_licencia, ciudad, patente_habitual, estado, tracto_id, licencia, licencia_vencimiento, tracto:tractos(id, patente, estado))")
            .eq("organization_id", activeOrganizationId),

        supabaseClient
            .from("viajes")
            .select("id, conductor_id, route_id, empresa_id, patente, ruta, empresa, estado, fecha_inicio, fecha_finalizacion, created_at")
            .eq("empresa_id", activeOrganizationId)
            .order("created_at", { ascending: false }),

        supabaseClient
            .from("routes")
            .select("id, organization_id, name, active")
            .eq("organization_id", activeOrganizationId)
            .order("name")
    ]);

    if (driversResponse.error) {
        throw new Error(driversResponse.error.message);
    }

    if (tripsResponse.error) {
        throw new Error(tripsResponse.error.message);
    }

    if (routesResponse.error) {
        throw new Error(routesResponse.error.message);
    }

    renderPools(
        driversResponse.data || [],
        tripsResponse.data || [],
        routesResponse.data || []
    );
}

assignmentRoute.addEventListener("change", function () {
    const route = currentRoutes.find(function (item) {
        return item.id === assignmentRoute.value;
    });
    assignmentRouteName.value = route?.name || "";
    assignmentCompany.value = activeOrganization?.name || "";
});

assignmentForm.addEventListener("submit", async function (event) {

    event.preventDefault();

    if (!canAssignOperations) {
        return;
    }

    const conductor =
        currentConductors.find(function (item) {
            return item.id === assignmentConductorId.value;
        });

    const patente =
        normalizePlate(
            conductor?.tracto?.patente ||
            conductor?.patente_habitual ||
            ""
        );

    const route =
        currentRoutes.find(function (item) {
            return item.id === assignmentForm.elements["route_id"].value &&
                item.organization_id === activeOrganizationId &&
                item.active;
        });

    const ruta =
        route?.name || null;

        const empresa =
            assignmentCompany.value || null;

    const estado =
        assignmentForm.elements["estado"].value;

    if (!conductor || !route || !patente || !estado) {
        assignmentError.innerText = "Completa los datos de la operación.";
        return;
    }

    const activeAssignment =
        getAssignmentByDriver(currentTrips)[conductor.id];

    if (activeAssignment) {
        assignmentError.innerText = "Este conductor ya tiene un viaje activo.";
        return;
    }

    const submitButton =
        assignmentForm.querySelector(".assignment-submit");

    submitButton.disabled = true;
    assignmentError.innerText = "";

    const {
        error
    } =
        await supabaseClient
            .from("viajes")
            .insert({
                patente,
                conductor: conductor.nombre,
                conductor_id: conductor.id,
                route_id: route?.id || null,
                empresa_id: activeOrganizationId,
                empresa,
                ruta,
                estado,
                fecha_inicio: new Date().toISOString(),
                fecha_finalizacion: null
            });

    if (error) {
        assignmentError.innerText =
            "No fue posible crear el viaje.";
        submitButton.disabled = false;
        return;
    }

    closeAssignment();
    await loadDriverPool();

});

document.addEventListener("click", function (event) {
    const inviteButton = event.target.closest(".invite-driver-button");

    if (inviteButton) {
        createDriverInvite();
        return;
    }

    const returnAvailableButton =
        event.target.closest(".return-available-button");

    if (returnAvailableButton) {
        returnCompletedTripToAvailable(returnAvailableButton.dataset.tripId);
        return;
    }

    const approveButton = event.target.closest(".approve-driver-button");
    const rejectButton = event.target.closest(".reject-driver-button");

    if (approveButton || rejectButton) {
        if (!canManageDrivers) {
            return;
        }

        const conductorId =
            (approveButton || rejectButton).dataset.conductorId;
        const rpcName = approveButton
            ? "approve_organization_driver"
            : "reject_organization_driver";

        supabaseClient
            .rpc(rpcName, {
                p_organization_id: activeOrganizationId,
                p_conductor_id: conductorId
            })
            .then(async function (response) {
                if (response.error) {
                    alert(response.error.message || "No fue posible actualizar la solicitud.");
                    return;
                }
                await loadDriverPool();
            });
        return;
    }

    const removeRouteButton =
        event.target.closest(".remove-route-button");

    if (removeRouteButton) {
        if (!canAssignOperations) {
            return;
        }

        const confirmed =
            window.confirm("¿Retirar este conductor de la ruta actual?");

        if (!confirmed) {
            return;
        }

        const tripId =
            removeRouteButton.dataset.tripId;

        supabaseClient
            .rpc("finalizar_viaje", {
                p_viaje_id: tripId
            })
            .then(async function (response) {
                if (response.error) {
                    const message = response.error.message ||
                        "No fue posible finalizar el viaje.";
                    alert(`No fue posible finalizar el viaje: ${message}`);
                    return;
                }

                await loadDriverPool();
            });

        return;
    }

    const profileButton =
        event.target.closest(".profile-button");

    if (profileButton) {
        openDriverProfile(profileButton.dataset.conductorId);
        return;
    }

    const button =
        event.target.closest(".assignment-button");

    if (button && !button.disabled) {
        const conductor =
            currentConductors.find(function (item) {
                return item.id === button.dataset.conductorId;
            });

        if (conductor) {
            openAssignment(conductor);
        }
    }

    if (event.target === assignmentModal) {
        closeAssignment();
    }
});

document
    .getElementById("closeAssignment")
    .addEventListener("click", closeAssignment);

closeDriverProfileButton
    .addEventListener("click", function () {
        driverProfileModal.hidden = true;
    });

document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
        closeAssignment();
        driverProfileModal.hidden = true;
    }
});

initializeOperatorSession()
    .then(function (authenticated) {
        if (!authenticated) {
            return;
        }

        return loadDriverPool();
    })
    .then(function () {
        setConnectionStatus(true);
    })
    .catch(function (error) {
        console.error("FLEETOPS DRIVER POOL ERROR:", error);
        setConnectionStatus(false);
        renderEmpty(
            "ERROR AL CARGAR CONDUCTORES",
            "No fue posible obtener los datos desde Supabase."
        );
    });
