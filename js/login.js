const loginForm =
    document.getElementById("loginForm");

const googleButton =
    document.getElementById("googleButton");

const loginError =
    document.getElementById("loginError");

const loginTitle =
    document.getElementById("loginTitle");

const loginCopy =
    document.getElementById("loginCopy");

const emailButton =
    document.getElementById("emailButton");

const modeButton =
    document.getElementById("modeButton");

const loginFormElements = [
    loginForm,
    googleButton,
    modeButton,
    document.querySelector(".login-divider")
];

const organizationPanel =
    document.getElementById("organizationPanel");

const organizationList =
    document.getElementById("organizationList");

const organizationCreateForm =
    document.getElementById("organizationCreateForm");

const organizationName =
    document.getElementById("organizationName");

const organizationCreateButton =
    document.getElementById("organizationCreateButton");

const organizationTitle =
    document.getElementById("organizationTitle");

const organizationCopy =
    document.querySelector(".organization-copy");

const organizationError =
    document.getElementById("organizationError");

const organizationBackButton =
    document.getElementById("organizationBackButton");

let isSignUpMode = false;
const inviteToken =
    new URLSearchParams(window.location.search).get("invite");

function getAuthRedirectUrl() {
    const params = new URLSearchParams();
    const nextPath = getNextPath();
    if (nextPath) {
        params.set("next", nextPath);
    }
    if (inviteToken) {
        params.set("invite", inviteToken);
    }
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
}

function getNextPath() {
    const requestedPath =
        new URLSearchParams(window.location.search).get("next");

    if (
        requestedPath &&
        requestedPath.startsWith("/") &&
        !requestedPath.startsWith("//")
    ) {
        return requestedPath;
    }

    return "dashboard.html";
}

async function redirectAfterLogin() {
    const {
        data: sessionData,
        error: sessionError
    } = await supabaseClient.auth.getSession();

    if (sessionError) {
        throw sessionError;
    }

    if (!sessionData.session) {
        window.location.replace(getNextPath());
        return;
    }

    const { data: isPlatformOwner, error: platformOwnerError } = await supabaseClient.rpc(
        "is_fleetops_platform_owner"
    );
    if (platformOwnerError) {
        throw platformOwnerError;
    }
    if (isPlatformOwner) {
        window.location.replace("fleetops-admin.html");
        return;
    }

    if (!getActiveOrganizationId()) {
        window.location.replace(getNextPath());
        return;
    }

    const {
        data: memberships,
        error: membershipsError
    } = await supabaseClient
        .from("organization_members")
        .select("role")
        .eq("organization_id", getActiveOrganizationId())
        .eq("user_id", sessionData.session.user.id)
        .limit(1);

    if (membershipsError) {
        throw membershipsError;
    }

    if (memberships && memberships[0] && memberships[0].role === "customer") {
        window.location.replace("customer-dashboard.html");
        return;
    }

    window.location.replace(getNextPath());
}

function setLoginControlsVisible(visible) {
    loginFormElements.forEach(function (element) {
        if (element) {
            element.hidden = !visible;
        }
    });
}

function showOrganizationPanel() {
    organizationPanel.hidden = false;
    setLoginControlsVisible(false);
}

function showLoginPanel() {
    organizationPanel.hidden = true;
    setLoginControlsVisible(true);
    organizationCreateForm.hidden = true;
    organizationList.hidden = false;
    organizationError.innerText = "";
}

function showOrganizationCreationPanel() {
    organizationPanel.hidden = false;
    setLoginControlsVisible(false);
    organizationList.hidden = true;
    organizationCreateForm.hidden = false;
    organizationBackButton.hidden = true;
    organizationName.value = "";
    organizationName.focus();
}

function renderOrganizations(organizations) {
    organizationList.innerHTML = "";
    organizationList.hidden = false;
    organizationCreateForm.hidden = true;
    organizationBackButton.hidden = false;

    organizations.forEach(function (organization) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "organization-button";
        button.innerText = organization.name || "Organización sin nombre";
        button.addEventListener("click", async function () {
            setActiveOrganizationId(organization.id);
            await redirectAfterLogin();
        });
        organizationList.appendChild(button);
    });
}

async function continueAfterAuthentication() {
    loginError.innerText = "";

    try {
        if (inviteToken) {
            const { data, error } = await supabaseClient.rpc(
                "accept_member_invite",
                { p_token: inviteToken }
            );
            if (error) {
                throw error;
            }

            const acceptedInvite = Array.isArray(data) ? data[0] : data;
            if (!acceptedInvite || !acceptedInvite.organization_id) {
                throw new Error("La invitación no pudo ser confirmada.");
            }

            setActiveOrganizationId(acceptedInvite.organization_id);
            if (acceptedInvite.role === "customer") {
                window.location.replace("customer-dashboard.html");
                return;
            }
            await redirectAfterLogin();
            return;
        }

        const { data: isPlatformOwner, error: platformOwnerError } = await supabaseClient.rpc(
            "is_fleetops_platform_owner"
        );
        if (platformOwnerError) {
            throw platformOwnerError;
        }
        if (isPlatformOwner) {
            window.location.replace("fleetops-admin.html");
            return;
        }

        const context = await resolveOrganizationContext();

        if (context.organizations.length === 0) {
            clearActiveOrganizationId();
            showOrganizationCreationPanel();
            organizationTitle.innerText = "CONFIGURA TU EMPRESA";
            organizationCopy.innerText = "Es el primer acceso de tu empresa. Crea la organización para comenzar.";
            organizationList.innerHTML = "";
            organizationError.innerText = "";
            return;
        }

        if (context.organizations.length === 1) {
            setActiveOrganizationId(context.organizations[0].id);
            await redirectAfterLogin();
            return;
        }

        showOrganizationPanel();
        organizationTitle.innerText = "Selecciona una organización";
        organizationCopy.innerText = "Elige la organización que quieres abrir en la torre de control.";
        renderOrganizations(context.organizations);
    }
    catch (error) {
        console.error("PRÆTOR FleetOps: no fue posible resolver organizaciones", error);
        if (inviteToken) {
            setLoginControlsVisible(true);
            loginError.innerText = error.message || "No fue posible aceptar la invitación.";
            return;
        }
        showOrganizationPanel();
        organizationTitle.innerText = "No se pudo cargar tu organización";
        organizationCopy.innerText = "La sesión existe, pero no fue posible consultar tus organizaciones.";
        organizationList.innerHTML = "";
        organizationError.innerText = "Intenta nuevamente o contacta al administrador de tu operación.";
    }
}

organizationCreateForm.addEventListener("submit", async function (event) {
    event.preventDefault();

    const name = organizationName.value.trim();
    if (!name) {
        organizationError.innerText = "Ingresa el nombre de la empresa.";
        organizationName.focus();
        return;
    }

    organizationError.innerText = "";
    organizationCreateButton.disabled = true;
    organizationCreateButton.innerText = "CREANDO EMPRESA...";

    const { data, error } = await supabaseClient.rpc(
        "create_organization_for_current_user",
        { p_name: name }
    );

    if (error) {
        console.error("PRÆTOR FleetOps: no fue posible crear la organización", error);
        organizationError.innerText =
            error.message || "No fue posible crear la organización.";
        organizationCreateButton.disabled = false;
        organizationCreateButton.innerText = "CREAR EMPRESA";
        return;
    }

    const createdOrganization = Array.isArray(data) ? data[0] : data;
    if (!createdOrganization || !createdOrganization.organization_id) {
        organizationError.innerText = "La organización no pudo ser confirmada.";
        organizationCreateButton.disabled = false;
        organizationCreateButton.innerText = "CREAR EMPRESA";
        return;
    }

    setActiveOrganizationId(createdOrganization.organization_id);
    await redirectAfterLogin();
});

async function redirectIfAuthenticated() {
    const {
        data
    } =
        await supabaseClient.auth.getSession();

    if (data.session) {
        await continueAfterAuthentication();
    }
}

function setLoginMode(signUpMode) {

    isSignUpMode = signUpMode;
    loginTitle.innerText =
        signUpMode ? "Crear cuenta" : "Inicio de sesión";
    loginCopy.innerText =
        signUpMode
            ? "Crea el acceso de un operador de la torre de control."
            : "Acceso para operadores de la operación.";
    emailButton.innerText =
        signUpMode ? "CREAR CUENTA" : "INICIAR SESIÓN";
    modeButton.innerText =
        signUpMode
            ? "YA TENGO UNA CUENTA · INICIAR SESIÓN"
            : "SIGN UP · CREAR CUENTA";
    loginError.innerText = "";

}

modeButton.addEventListener("click", function () {
    setLoginMode(!isSignUpMode);
});

organizationBackButton.addEventListener("click", function () {
    showLoginPanel();
    setLoginMode(false);
});

loginForm.addEventListener("submit", async function (event) {
    event.preventDefault();

    const email =
        loginForm.elements["email"].value.trim();

    const password =
        loginForm.elements["password"].value;

    loginError.innerText = "";
    emailButton.disabled = true;

    if (isSignUpMode) {

        const redirectTo = getAuthRedirectUrl();

        const {
            data,
            error
        } =
            await supabaseClient.auth.signUp({
                email,
                password,
                options: {
                    emailRedirectTo: redirectTo
                }
            });

        if (error) {
            loginError.innerText =
                "No fue posible crear la cuenta.";
            emailButton.disabled = false;
            return;
        }

        if (data.session) {
            await continueAfterAuthentication();
            return;
        }

        loginError.innerText =
            "Cuenta creada. Revisa tu email para confirmarla.";
        emailButton.disabled = false;
        return;
    }

    const {
        error
    } =
        await supabaseClient.auth.signInWithPassword({
            email,
            password
        });

    if (error) {
        loginError.innerText =
            "No fue posible iniciar sesión. Revisa tus datos.";
        emailButton.disabled = false;
        return;
    }

    await continueAfterAuthentication();
});

googleButton.addEventListener("click", async function () {

    loginError.innerText = "";
    googleButton.disabled = true;
    googleButton.innerText = "CONECTANDO CON GOOGLE...";

    const redirectTo = getAuthRedirectUrl();

    const {
        error
    } =
        await supabaseClient.auth.signInWithOAuth({
            provider: "google",
            options: {
                redirectTo
            }
        });

    if (error) {
        loginError.innerText =
            "Google no está disponible para este proyecto.";
        googleButton.disabled = false;
        googleButton.innerHTML =
            '<span class="google-mark">G</span> CONTINUAR CON GOOGLE';
    }
});

async function loadInviteContext() {
    if (!inviteToken) {
        return;
    }

    const { data, error } = await supabaseClient.rpc(
        "get_member_invite_context",
        { p_token: inviteToken }
    );

    if (error) {
        loginError.innerText = "La invitación no existe o no está disponible.";
        return;
    }

    const context = Array.isArray(data) ? data[0] : data;
    if (!context) {
        loginError.innerText = "La invitación no existe o no está disponible.";
        return;
    }

    if (context.invite_status === "expired") {
        loginError.innerText = "Esta invitación expiró.";
    } else if (context.invite_status === "used") {
        loginError.innerText = "Esta invitación ya fue utilizada.";
    } else if (context.role === "customer") {
        const { data: customerData, error: customerError } = await supabaseClient.rpc(
            "get_customer_member_invite_context",
            { p_token: inviteToken }
        );
        if (customerError) {
            console.error("PRÆTOR FleetOps: no fue posible cargar el contexto de invitación del cliente", customerError);
            loginError.innerText = "No fue posible verificar la invitación del cliente.";
            return;
        }

        const customerContext = Array.isArray(customerData) ? customerData[0] : customerData;
        if (!customerContext || customerContext.invite_status !== "pending") {
            loginError.innerText = customerContext?.invite_status === "expired"
                ? "Esta invitación expiró."
                : "La invitación del cliente no está disponible.";
            return;
        }
        loginCopy.innerText = `Has sido invitado como usuario de cliente ${customerContext.customer_name} por ${customerContext.organization_name}. Inicia sesión con el email invitado.`;
    } else if (context.role === "owner") {
        loginCopy.innerText = `Has sido invitado como primer owner de ${context.organization_name}. Crea tu cuenta o inicia sesión con el email invitado para activar la empresa.`;
    } else {
        loginCopy.innerText = `Has sido invitado a trabajar en ${context.organization_name}. Inicia sesión con el email invitado.`;
    }
}

loadInviteContext().finally(redirectIfAuthenticated);
