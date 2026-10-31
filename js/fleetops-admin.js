const provisionForm = document.getElementById("provisionForm");
const organizationNameInput = document.getElementById("organizationName");
const ownerEmailInput = document.getElementById("ownerEmail");
const provisionButton = document.getElementById("provisionButton");
const adminError = document.getElementById("adminError");
const invitePanel = document.getElementById("invitePanel");
const inviteMessage = document.getElementById("inviteMessage");
const inviteUrl = document.getElementById("inviteUrl");
const copyInviteButton = document.getElementById("copyInviteButton");
const organizationList = document.getElementById("organizationList");
const organizationCount = document.getElementById("organizationCount");
const pendingInviteCount = document.getElementById("pendingInviteCount");
const logoutButton = document.getElementById("logoutButton");

function escapeHTML(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function formatDate(value) {
    const date = new Date(value);
    return Number.isNaN(date.getTime())
        ? "--"
        : date.toLocaleDateString("es-CL");
}

function renderOrganizations(organizations) {
    organizationCount.innerText = organizations.length;
    pendingInviteCount.innerText = organizations.filter(
        organization => organization.invite_status === "Pendiente"
    ).length;

    if (!organizations.length) {
        organizationList.innerHTML = '<div class="admin-empty">Todavía no hay organizaciones.</div>';
        return;
    }

    organizationList.innerHTML = organizations.map(organization => {
        const statusClass = organization.invite_status === "Pendiente"
            ? "pending"
            : organization.invite_status === "Aceptada"
                ? "accepted"
                : organization.invite_status === "Expirada"
                    ? "expired"
                    : "";

        return `
            <article class="admin-organization">
                <div>
                    <div class="admin-organization-name">${escapeHTML(organization.organization_name)}</div>
                    <div class="admin-organization-meta">Creada ${escapeHTML(formatDate(organization.created_at))}</div>
                </div>
                <div>
                    <div class="admin-organization-email">${escapeHTML(organization.first_user_email || "Sin usuario de primer acceso")}</div>
                    <div class="admin-organization-meta">Primer owner</div>
                </div>
                <div class="admin-organization-status ${statusClass}">${escapeHTML(organization.invite_status)}</div>
            </article>
        `;
    }).join("");
}

async function loadOrganizations() {
    const { data, error } = await supabaseClient.rpc("list_fleetops_platform_organizations");
    if (error) {
        throw error;
    }
    renderOrganizations(data || []);
}

async function initializePlatformDashboard() {
    const { data: sessionData, error: sessionError } = await supabaseClient.auth.getSession();
    if (sessionError) {
        throw sessionError;
    }

    if (!sessionData.session) {
        window.location.replace("login.html?next=fleetops-admin.html");
        return;
    }

    const { data: authorized, error: authorizationError } = await supabaseClient.rpc(
        "is_fleetops_platform_owner"
    );
    if (authorizationError) {
        throw authorizationError;
    }

    if (authorized !== true) {
        window.location.replace("dashboard.html");
        return;
    }

    await loadOrganizations();
}

provisionForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    adminError.innerText = "";
    invitePanel.hidden = true;
    provisionButton.disabled = true;
    provisionButton.innerText = "CREANDO...";

    try {
        const { data, error } = await supabaseClient.rpc(
            "create_platform_organization_invite",
            {
                p_organization_name: organizationNameInput.value.trim(),
                p_email: ownerEmailInput.value.trim()
            }
        );
        if (error) {
            throw error;
        }

        const invite = Array.isArray(data) ? data[0] : data;
        if (!invite || !invite.invite_token) {
            throw new Error("La invitación del primer owner no fue confirmada.");
        }

        inviteUrl.value = new URL(invite.invite_url, window.location.href).href;
        inviteMessage.innerText = `${invite.organization_name} · ${invite.invite_email}`;
        invitePanel.hidden = false;
        provisionForm.reset();
        await loadOrganizations();
    } catch (error) {
        console.error("PRÆTOR FleetOps: no fue posible provisionar la organización", error);
        adminError.innerText = error.message || "No fue posible crear la empresa y su invitación.";
    } finally {
        provisionButton.disabled = false;
        provisionButton.innerText = "CREAR EMPRESA E INVITAR OWNER";
    }
});

copyInviteButton.addEventListener("click", async function () {
    try {
        await navigator.clipboard.writeText(inviteUrl.value);
        copyInviteButton.innerText = "ENLACE COPIADO";
    } catch (error) {
        console.error("PRÆTOR FleetOps: no fue posible copiar el enlace", error);
        adminError.innerText = "No se pudo copiar automáticamente. Selecciona y copia el enlace.";
        inviteUrl.focus();
        inviteUrl.select();
    }
});

logoutButton.addEventListener("click", async function () {
    const { error } = await supabaseClient.auth.signOut();
    if (error) {
        adminError.innerText = error.message || "No fue posible cerrar la sesión.";
        return;
    }
    window.location.replace("login.html");
});

initializePlatformDashboard().catch(function (error) {
    console.error("PRÆTOR FleetOps: no fue posible abrir administración global", error);
    adminError.innerText = error.message || "No fue posible verificar el acceso de plataforma.";
    provisionForm.hidden = true;
});
