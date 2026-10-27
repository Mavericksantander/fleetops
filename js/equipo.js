const inviteButton = document.getElementById("inviteButton");
const inviteModal = document.getElementById("inviteModal");
const inviteForm = document.getElementById("inviteForm");
const inviteTitle = document.getElementById("inviteTitle");
const inviteEmail = document.getElementById("inviteEmail");
const inviteRole = document.getElementById("inviteRole");
const inviteCustomerField = document.getElementById("inviteCustomerField");
const inviteCustomer = document.getElementById("inviteCustomer");
const generateInviteButton = document.getElementById("generateInviteButton");
const inviteResult = document.getElementById("inviteResult");
const inviteUrl = document.getElementById("inviteUrl");
const copyInviteButton = document.getElementById("copyInviteButton");
const inviteError = document.getElementById("inviteError");
const teamList = document.getElementById("teamList");
const teamError = document.getElementById("teamError");
const createCustomerForm = document.getElementById("customerForm");
const customerNameInput = document.getElementById("customerName");
const customerContactInput = document.getElementById("customerContact");
const customerEmailInput = document.getElementById("customerEmail");
const customerPhoneInput = document.getElementById("customerPhone");
const customerMessage = document.getElementById("customerMessage");
const customerList = document.getElementById("customerList");
const customerAccessForm = document.getElementById("customerAccessForm");
const accessCustomer = document.getElementById("accessCustomer");
const accessScope = document.getElementById("accessScope");
const accessOperation = document.getElementById("accessOperation");
const customerAccessError = document.getElementById("customerAccessError");

let activeOrganizationId = null;
let customers = [];
let routes = [];
let trips = [];
let customerAccessRows = [];
let customerUsers = [];
let customerInvites = [];
let canManageCustomers = false;

function escapeTeamText(value) {
    const element = document.createElement("span");
    element.textContent = value || "";
    return element.innerHTML;
}

function setCustomerInviteMode(customerId = "") {
    const customerMode = Boolean(customerId);
    inviteCustomerField.hidden = !customerMode;
    inviteCustomer.required = customerMode;
    inviteRole.disabled = customerMode;
    inviteTitle.innerText = customerMode
        ? "INVITAR USUARIO DEL CLIENTE"
        : "INVITAR COLABORADOR";
    if (customerMode) {
        inviteCustomer.value = customerId;
    }
}

function closeInviteModal() {
    inviteModal.hidden = true;
    inviteError.innerText = "";
}

function renderTeam(rows, organizationId) {
    const visibleRows = (rows || []).filter(row =>
        row.organization_id === organizationId && row.role !== "customer"
    );
    teamList.innerHTML = "";

    if (!visibleRows.length) {
        teamList.innerHTML = '<div class="team-empty">No hay miembros para mostrar.</div>';
        return;
    }

    visibleRows.forEach(row => {
        const item = document.createElement("article");
        item.className = "team-row";
        item.innerHTML = `
            <div><span class="team-name">${escapeTeamText(row.display_name || row.email)}</span><span class="team-email">${escapeTeamText(row.email)}</span></div>
            <span class="team-role">${escapeTeamText(row.role)}</span>
            <span class="team-status ${escapeTeamText(row.status)}">${escapeTeamText(row.status === "active" ? "ACTIVO" : "PENDIENTE")}</span>
            <span class="team-meta">${row.created_at ? new Date(row.created_at).toLocaleDateString("es-CL") : ""}</span>`;
        teamList.appendChild(item);
    });
}

function getAccessLabel(access) {
    if (access.is_excluded) {
        const trip = trips.find(item => item.id === access.trip_id);
        return `Exclusión · ${trip?.ruta || trip?.id || "Viaje"}`;
    }
    if (access.route_id) {
        const route = routes.find(item => item.id === access.route_id);
        return `Ruta · ${route?.name || "Ruta"}`;
    }
    const trip = trips.find(item => item.id === access.trip_id);
    return `Viaje · ${trip?.ruta || trip?.id || "Viaje"}`;
}

function renderCustomers() {
    customerList.innerHTML = "";
    const activeCustomers = customers.filter(customer => customer.is_active);

    if (!customers.length) {
        customerList.innerHTML = '<div class="team-empty">No hay clientes registrados.</div>';
    } else {
        customers.forEach(customer => {
            const accessRows = customerAccessRows.filter(row => row.customer_id === customer.id && row.active);
            const userCount = customerUsers.filter(row => row.customer_id === customer.id).length;
            const invites = customerInvites.filter(row => row.customer_id === customer.id);
            const item = document.createElement("article");
            item.className = "customer-card";
            const accessHtml = accessRows.length
                ? accessRows.map(access => `
                    <div class="customer-access-row">
                        <span>${escapeTeamText(getAccessLabel(access))}</span>
                        <button type="button" class="text-action" data-action="revoke-access" data-access-id="${escapeTeamText(access.id)}">REVOCAR</button>
                    </div>
                `).join("")
                : '<div class="team-email">Sin operaciones autorizadas</div>';
            const inviteHtml = invites.map(invite => {
                const statusClass = invite.consumed_at
                    ? "accepted"
                    : new Date(invite.expires_at) <= new Date()
                        ? "expired"
                        : "pending";
                const statusLabel = statusClass === "accepted"
                    ? "ACEPTADA"
                    : statusClass === "expired"
                        ? "EXPIRADA"
                        : "PENDIENTE";
                return `<span class="customer-invite-status ${statusClass}">${escapeTeamText(invite.email)} · ${statusLabel}</span>`;
            }).join("");
            item.innerHTML = `
                <div class="customer-card-header">
                    <div>
                        <span class="team-name">${escapeTeamText(customer.name)}</span>
                        <span class="team-email">${escapeTeamText(customer.email || "Sin email de contacto")}</span>
                    </div>
                    <span class="team-status ${customer.is_active ? "active" : "inactive"}">${customer.is_active ? "ACTIVO" : "INACTIVO"}</span>
                </div>
                <div class="customer-card-meta">
                    <span>Usuarios: ${userCount}</span>
                    <span>Accesos activos: ${accessRows.length}</span>
                    <span>${escapeTeamText(customer.contact_name || "Sin contacto")}</span>
                </div>
                ${inviteHtml ? `<div class="customer-invites">${inviteHtml}</div>` : ""}
                <div class="customer-access-list">${accessHtml}</div>
                <div class="customer-actions">
                    ${customer.is_active ? `<button type="button" class="text-action" data-action="invite-customer" data-customer-id="${escapeTeamText(customer.id)}">INVITAR USUARIO</button>` : ""}
                    <button type="button" class="text-action" data-action="toggle-customer" data-customer-id="${escapeTeamText(customer.id)}" data-active="${customer.is_active ? "true" : "false"}">${customer.is_active ? "DESACTIVAR CLIENTE" : "ACTIVAR CLIENTE"}</button>
                </div>`;
            customerList.appendChild(item);
        });
    }

    const options = activeCustomers.map(customer =>
        `<option value="${escapeTeamText(customer.id)}">${escapeTeamText(customer.name)}</option>`
    ).join("");
    accessCustomer.innerHTML = options || '<option value="">No hay clientes activos</option>';
    inviteCustomer.innerHTML = options || '<option value="">No hay clientes activos</option>';
    renderOperationOptions();
}

function renderOperationOptions() {
    const scope = accessScope.value;
    const options = scope === "route"
        ? routes.map(route => `<option value="${escapeTeamText(route.id)}">${escapeTeamText(route.name)}</option>`)
        : trips.map(trip => {
            const title = [trip.ruta, trip.patente, trip.estado].filter(Boolean).join(" · ");
            return `<option value="${escapeTeamText(trip.id)}">${escapeTeamText(title || trip.id)}</option>`;
        });

    accessOperation.innerHTML = options.length
        ? options.join("")
        : `<option value="">${scope === "route" ? "No hay rutas activas" : "No hay viajes disponibles"}</option>`;
    accessOperation.disabled = options.length === 0;
    document.getElementById("grantAccessButton").disabled =
        options.length === 0 || !customers.some(customer => customer.is_active);
}

async function loadCustomerData() {
    const customerResult = await supabaseClient
        .from("customers")
        .select("id, organization_id, name, contact_name, email, phone, is_active, created_at")
        .eq("organization_id", activeOrganizationId)
        .order("created_at", { ascending: false });

    if (customerResult.error) {
        throw new Error(`No se pudieron consultar los clientes: ${customerResult.error.message}`);
    }

    customers = customerResult.data || [];
    renderCustomers();

    const invitationsRequest = canManageCustomers
        ? supabaseClient
            .from("organization_member_invites")
            .select("id, customer_id, email, consumed_at, expires_at")
            .eq("organization_id", activeOrganizationId)
            .eq("role", "customer")
        : Promise.resolve({ data: [], error: null });
    const [routeResult, usersResult, accessResult, tripResult, invitesResult] = await Promise.all([
        supabaseClient
            .from("routes")
            .select("id, name, active")
            .eq("organization_id", activeOrganizationId)
            .eq("active", true)
            .order("name"),
        supabaseClient
            .from("customer_users")
            .select("id, customer_id, user_id")
            .eq("organization_id", activeOrganizationId),
        supabaseClient
            .from("customer_operation_access")
            .select("id, customer_id, route_id, trip_id, active, is_excluded")
            .eq("organization_id", activeOrganizationId),
        supabaseClient
            .from("viajes")
            .select("id, empresa_id, route_id, ruta, estado, patente, created_at")
            .eq("empresa_id", activeOrganizationId)
            .order("created_at", { ascending: false }),
        invitationsRequest
    ]);

    for (const result of [routeResult, usersResult, accessResult, tripResult, invitesResult]) {
        if (result.error) {
            throw result.error;
        }
    }

    routes = routeResult.data || [];
    customerUsers = usersResult.data || [];
    customerAccessRows = accessResult.data || [];
    trips = tripResult.data || [];
    customerInvites = invitesResult.data || [];

    const routeIds = routes.map(route => route.id);
    if (routeIds.length) {
        const { data: routeTrips, error: routeTripsError } = await supabaseClient
            .from("viajes")
            .select("id, empresa_id, route_id, ruta, estado, patente, created_at")
            .in("route_id", routeIds)
            .order("created_at", { ascending: false });
        if (routeTripsError) {
            throw routeTripsError;
        }
        const tripsById = new Map(trips.map(trip => [trip.id, trip]));
        (routeTrips || []).forEach(trip => {
            if (trip.empresa_id === activeOrganizationId) {
                tripsById.set(trip.id, trip);
            }
        });
        trips = [...tripsById.values()];
    }

    renderCustomers();
    customerAccessError.innerText = customers.some(customer => customer.is_active)
        ? ""
        : "No hay clientes activos en esta organización. Revisa que se haya creado en la organización seleccionada.";
}

async function initializeTeam() {
    const context = await resolveOrganizationContext();
    if (!context.session || !context.activeOrganization) {
        window.location.replace("login.html?next=equipo.html");
        return;
    }

    activeOrganizationId = context.activeOrganization.id;
    const { data: memberships, error: membershipError } = await supabaseClient
        .from("organization_members")
        .select("role")
        .eq("organization_id", activeOrganizationId)
        .eq("user_id", context.session.user.id)
        .limit(1);

    if (membershipError) {
        throw membershipError;
    }

    const role = memberships && memberships[0] ? memberships[0].role : null;
    if (role === "customer") {
        window.location.replace("customer-dashboard.html");
        return;
    }
    const canManage = role === "owner" || role === "admin" ||
        context.activeOrganization.owner_id === context.session.user.id;
    canManageCustomers = canManage;
    inviteButton.hidden = !canManage;
    createCustomerForm.hidden = !canManage;
    customerAccessForm.hidden = !canManage;

    const { data: rows, error: teamLoadError } = await supabaseClient.rpc("list_current_user_organization_team");
    if (teamLoadError) {
        throw teamLoadError;
    }
    renderTeam(rows, activeOrganizationId);
    await loadCustomerData();
}

createCustomerForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    customerMessage.innerText = "";
    const { data, error } = await supabaseClient.rpc("create_customer_for_organization", {
        p_organization_id: activeOrganizationId,
        p_name: customerNameInput.value.trim(),
        p_contact_name: customerContactInput.value.trim(),
        p_email: customerEmailInput.value.trim(),
        p_phone: customerPhoneInput.value.trim()
    });

    if (error) {
        customerMessage.innerText = error.message || "No fue posible crear el cliente.";
        return;
    }

    const created = Array.isArray(data) ? data[0] : data;
    customerMessage.innerText = created ? `Cliente creado: ${created.customer_name}` : "Cliente creado.";
    createCustomerForm.reset();
    try {
        await loadCustomerData();
    } catch (loadError) {
        console.error("PRÆTOR FleetOps: cliente creado, pero no se pudo recargar la lista", loadError);
        customerAccessError.innerText =
            `Cliente creado, pero no se pudo cargar en el selector: ${loadError.message || "Error de lectura"}`;
    }
});

inviteButton.addEventListener("click", function () {
    inviteModal.hidden = false;
    inviteResult.hidden = true;
    inviteForm.reset();
    setCustomerInviteMode();
    inviteRole.disabled = false;
    inviteError.innerText = "";
    inviteEmail.focus();
});

document.getElementById("closeInviteButton").addEventListener("click", closeInviteModal);

inviteRole.addEventListener("change", function () {
    setCustomerInviteMode();
});

customerList.addEventListener("click", async function (event) {
    const button = event.target.closest("[data-action]");
    if (!button) {
        return;
    }

    const action = button.dataset.action;
    if (action === "invite-customer") {
        inviteModal.hidden = false;
        inviteResult.hidden = true;
        inviteForm.reset();
        setCustomerInviteMode(button.dataset.customerId);
        const customer = customers.find(item => item.id === button.dataset.customerId);
        inviteEmail.value = customer?.email || "";
        inviteError.innerText = "";
        inviteEmail.focus();
        return;
    }

    if (action === "revoke-access") {
        button.disabled = true;
        const { error } = await supabaseClient
            .from("customer_operation_access")
            .update({ active: false })
            .eq("id", button.dataset.accessId)
            .eq("organization_id", activeOrganizationId);
        if (error) {
            button.disabled = false;
            customerAccessError.innerText = error.message || "No fue posible revocar el acceso.";
            return;
        }
        customerAccessError.innerText = "Acceso revocado.";
        await loadCustomerData();
        return;
    }

    if (action === "toggle-customer") {
        const nextActive = button.dataset.active !== "true";
        button.disabled = true;
        const { error } = await supabaseClient
            .from("customers")
            .update({ is_active: nextActive })
            .eq("id", button.dataset.customerId)
            .eq("organization_id", activeOrganizationId);
        if (error) {
            button.disabled = false;
            teamError.innerText = error.message || "No fue posible actualizar el cliente.";
            return;
        }
        await loadCustomerData();
    }
});

accessScope.addEventListener("change", renderOperationOptions);

customerAccessForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    customerAccessError.innerText = "";
    const scope = accessScope.value;
    const payload = {
        organization_id: activeOrganizationId,
        customer_id: accessCustomer.value,
        route_id: scope === "route" ? accessOperation.value : null,
        trip_id: scope === "route" ? null : accessOperation.value,
        is_excluded: scope === "exclude",
        active: true
    };

    const { error } = await supabaseClient
        .from("customer_operation_access")
        .insert(payload);

    if (error) {
        customerAccessError.innerText = error.message || "No fue posible guardar el acceso.";
        return;
    }

    customerAccessError.innerText = scope === "exclude"
        ? "Viaje excluido de la ruta autorizada."
        : "Acceso otorgado.";
    await loadCustomerData();
});

inviteForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    inviteError.innerText = "";
    generateInviteButton.disabled = true;
    generateInviteButton.innerText = "GENERANDO...";

    const rpcName = inviteCustomerField.hidden
        ? "create_member_invite"
        : "create_customer_member_invite";
    const rpcArgs = inviteCustomerField.hidden
        ? {
            p_email: inviteEmail.value.trim(),
            p_role: inviteRole.value
        }
        : {
            p_email: inviteEmail.value.trim(),
            p_customer_id: inviteCustomer.value
        };
    const { data, error } = await supabaseClient.rpc(rpcName, rpcArgs);

    if (error) {
        inviteError.innerText = error.message || "No fue posible generar la invitación.";
        generateInviteButton.disabled = false;
        generateInviteButton.innerText = "GENERAR INVITACIÓN";
        return;
    }

    const invite = Array.isArray(data) ? data[0] : data;
    if (!invite || !invite.invite_token) {
        inviteError.innerText = "La invitación no pudo ser confirmada.";
        generateInviteButton.disabled = false;
        generateInviteButton.innerText = "GENERAR INVITACIÓN";
        return;
    }

    inviteUrl.value = new URL(invite.invite_url, window.location.href).href;
    inviteResult.hidden = false;
    generateInviteButton.disabled = false;
    generateInviteButton.innerText = "GENERAR INVITACIÓN";
});

copyInviteButton.addEventListener("click", async function () {
    await navigator.clipboard.writeText(inviteUrl.value);
    copyInviteButton.innerText = "ENLACE COPIADO";
});

initializeTeam().catch(function (error) {
    console.error("PRÆTOR FleetOps: no fue posible cargar clientes y equipo", error);
    const message = error.message || "No fue posible cargar clientes y equipo.";
    teamError.innerText = message;
    customerAccessError.innerText = `No se pudo llenar el selector de clientes: ${message}`;
});
