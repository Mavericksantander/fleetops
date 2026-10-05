const ACTIVE_ORGANIZATION_KEY = "praetor.active_organization_id";

function getActiveOrganizationId() {
    return window.localStorage.getItem(ACTIVE_ORGANIZATION_KEY);
}

function setActiveOrganizationId(organizationId) {
    if (!organizationId) {
        window.localStorage.removeItem(ACTIVE_ORGANIZATION_KEY);
        return;
    }

    window.localStorage.setItem(ACTIVE_ORGANIZATION_KEY, organizationId);
}

function clearActiveOrganizationId() {
    window.localStorage.removeItem(ACTIVE_ORGANIZATION_KEY);
}

async function getOrganizationMemberships() {
    const {
        data: sessionData,
        error: sessionError
    } = await supabaseClient.auth.getSession();

    if (sessionError) {
        throw sessionError;
    }

    if (!sessionData.session) {
        return {
            session: null,
            organizations: []
        };
    }

    const {
        data: memberships,
        error: membershipError
    } = await supabaseClient
        .from("organization_members")
        .select("organization_id, role")
        .eq("user_id", sessionData.session.user.id);

    if (membershipError) {
        throw membershipError;
    }

    const organizationIds = [
        ...new Set(
            (memberships || [])
                .map(membership => membership.organization_id)
                .filter(Boolean)
        )
    ];

    if (organizationIds.length === 0) {
        return {
            session: sessionData.session,
            organizations: []
        };
    }

    const {
        data: organizations,
        error: organizationError
    } = await supabaseClient
        .from("organizations")
        .select("id, name")
        .in("id", organizationIds)
        .order("name", { ascending: true });

    if (organizationError) {
        throw organizationError;
    }

    return {
        session: sessionData.session,
        organizations: organizations || []
    };
}

async function resolveOrganizationContext() {
    const context = await getOrganizationMemberships();

    if (!context.session) {
        return {
            ...context,
            activeOrganization: null
        };
    }

    const activeOrganizationId = getActiveOrganizationId();
    const activeOrganization = context.organizations.find(
        organization => organization.id === activeOrganizationId
    );

    if (activeOrganization) {
        return {
            ...context,
            activeOrganization
        };
    }

    if (context.organizations.length === 1) {
        setActiveOrganizationId(context.organizations[0].id);
        return {
            ...context,
            activeOrganization: context.organizations[0]
        };
    }

    clearActiveOrganizationId();
    return {
        ...context,
        activeOrganization: null
    };
}
