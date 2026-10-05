const inviteButton = document.getElementById("inviteButton");
const inviteModal = document.getElementById("inviteModal");
const inviteForm = document.getElementById("inviteForm");
const inviteEmail = document.getElementById("inviteEmail");
const inviteRole = document.getElementById("inviteRole");
const generateInviteButton = document.getElementById("generateInviteButton");
const inviteResult = document.getElementById("inviteResult");
const inviteUrl = document.getElementById("inviteUrl");
const copyInviteButton = document.getElementById("copyInviteButton");
const inviteError = document.getElementById("inviteError");
const teamList = document.getElementById("teamList");
const teamError = document.getElementById("teamError");

function escapeTeamText(value) {
    const element = document.createElement("span");
    element.textContent = value || "";
    return element.innerHTML;
}

function closeInviteModal() {
    inviteModal.hidden = true;
    inviteError.innerText = "";
}

function renderTeam(rows, organizationId) {
    const visibleRows = (rows || []).filter(row => row.organization_id === organizationId);
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

async function initializeTeam() {
    const context = await resolveOrganizationContext();
    if (!context.session || !context.activeOrganization) {
        window.location.replace("login.html?next=equipo.html");
        return;
    }

    const { data: memberships, error: membershipError } = await supabaseClient
        .from("organization_members")
        .select("role")
        .eq("organization_id", context.activeOrganization.id)
        .eq("user_id", context.session.user.id)
        .limit(1);

    if (membershipError) {
        throw membershipError;
    }

    const role = memberships && memberships[0] ? memberships[0].role : null;
    const canManage = role === "owner" || role === "admin" || context.activeOrganization.owner_id === context.session.user.id;
    inviteButton.hidden = !canManage;

    const { data: rows, error: teamLoadError } = await supabaseClient.rpc("list_current_user_organization_team");
    if (teamLoadError) {
        throw teamLoadError;
    }
    renderTeam(rows, context.activeOrganization.id);
}

inviteButton.addEventListener("click", function () {
    inviteModal.hidden = false;
    inviteResult.hidden = true;
    inviteForm.reset();
    inviteError.innerText = "";
    inviteEmail.focus();
});

document.getElementById("closeInviteButton").addEventListener("click", closeInviteModal);

inviteForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    inviteError.innerText = "";
    generateInviteButton.disabled = true;
    generateInviteButton.innerText = "GENERANDO...";

    const { data, error } = await supabaseClient.rpc("create_member_invite", {
        p_email: inviteEmail.value.trim(),
        p_role: inviteRole.value
    });

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
    console.error("PRÆTOR FleetOps: no fue posible cargar el equipo", error);
    teamError.innerText = error.message || "No fue posible cargar el equipo.";
});
