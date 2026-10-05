const routesContainer = document.getElementById("routesContainer");
const organizationSelect = document.getElementById("organizationSelect");
const routeForm = document.getElementById("routeForm");
const routeError = document.getElementById("routeError");
let activeOrganizationId = null;
let activeOrganization = null;

function escapeHTML(value){return String(value ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#039;");}

async function requireOperator(){
    const context=await resolveOrganizationContext();
    if(!context.session || !context.activeOrganization){
        window.location.replace(`login.html?next=${encodeURIComponent(window.location.pathname)}`);
        return false;
    }
    activeOrganizationId=context.activeOrganization.id;
    activeOrganization=context.activeOrganization;
    return true;
}

async function loadRouteData(){
    const routesResponse=await supabaseClient
        .from("routes")
        .select("id,organization_id,name,active,created_at")
        .eq("organization_id",activeOrganizationId)
        .order("created_at",{ascending:false});
    if(routesResponse.error) throw routesResponse.error;
    organizationSelect.innerHTML=`<option value="${escapeHTML(activeOrganization.id)}">${escapeHTML(activeOrganization.name || "Organización activa")}</option>`;
    organizationSelect.disabled=true;
    routesContainer.innerHTML=(routesResponse.data || []).length
        ? routesResponse.data.map(function(route){
            return `<article class="route-card">
                <div class="route-card-name">${escapeHTML(route.name)}</div>
                <div class="route-card-meta">${escapeHTML(activeOrganization.name || "ORGANIZACIÓN ACTIVA")}</div>
                <div class="route-status">${route.active ? "ACTIVA" : "INACTIVA"}</div>
            </article>`;
        }).join("")
        : `<div class="empty-state">
            <div class="empty-title">SIN RUTAS CONFIGURADAS</div>
            <div class="empty-text">Crea una ruta para que aparezca disponible en las asignaciones.</div>
        </div>`;
}

routeForm.addEventListener("submit",async function(event){
    event.preventDefault();
    routeError.innerText="";
    const organization_id=activeOrganizationId;
    const payload={
        organization_id,
        name: routeForm.elements["routeName"].value.trim()
    };
    if(!organization_id){routeError.innerText="No hay una organización activa.";return;}
    const {error}=await supabaseClient.from("routes").insert(payload);
    if(error){
        console.error("FLEETOPS ROUTE INSERT ERROR:",error);
        routeError.innerText=`No fue posible crear la ruta: ${error.message}`;
        return;
    }
    routeForm.reset();
    await loadRouteData();
});

requireOperator().then(function(authenticated){if(authenticated){return loadRouteData();}}).catch(function(error){console.error("FLEETOPS ROUTES ERROR",error);routesContainer.innerHTML="<div class=\"empty-state\"><div class=\"empty-title\">NO FUE POSIBLE CARGAR RUTAS</div></div>";});
