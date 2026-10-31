
// =====================================================
// FORMULARIO
// =====================================================

const fleetForm =
    document.getElementById("fleetForm");


if(!fleetForm){

    console.error(
        "ERROR: No se encontró #fleetForm"
    );

    throw new Error(
        "FleetOps: formulario no encontrado."
    );

}


// =====================================================
// ESTADOS
// =====================================================

function setStatus(button,status){

    document
        .querySelectorAll(".status")
        .forEach(btn => {

            btn.classList.remove("active");

        });


    button.classList.add("active");


    document.getElementById("estado").value =
        status;

    const incidentCategoryField =
        document.getElementById("incidentCategoryField");
    const incidentCategory =
        document.getElementById("incidentCategory");
    const isIncident =
        status === "Incidente";

    incidentCategoryField.hidden = !isIncident;
    incidentCategory.required = isIncident;

    if (!isIncident) {
        incidentCategory.value = "";
    }

}


// =====================================================
// GPS
// =====================================================

const gps =
    document.getElementById("gps");


if("geolocation" in navigator){

    navigator.geolocation.getCurrentPosition(

        function(position){

            const latitude =
                position.coords.latitude;


            const longitude =
                position.coords.longitude;


            const accuracy =
                position.coords.accuracy;


            document.getElementById("latitud").value =
                latitude;


            document.getElementById("longitud").value =
                longitude;


            document.getElementById("precision").value =
                accuracy;


            const mapsURL =
                `https://www.google.com/maps?q=${latitude},${longitude}`;


            document.getElementById("maps").value =
                mapsURL;


            gps.innerHTML =
                "GPS LOCK OK";

        },


        function(error){

            console.error(
                "GPS ERROR:",
                error
            );


            gps.innerHTML =
                "GPS NO DISPONIBLE";

        },


        {

            enableHighAccuracy:true,

            timeout:10000,

            maximumAge:0

        }

    );

}


else{

    gps.innerHTML =
        "GPS NO SOPORTADO";

}


// =====================================================
// NORMALIZAR TELÉFONO
// =====================================================

function normalizePhone(value){

    return String(value || "")
        .replace(/[^\d]/g, "");

}

function normalizeRut(value){

    return String(value || "")
        .replace(/[^0-9kK]/g, "")
        .toUpperCase();

}

function normalizeDriverId(value){

    return String(value || "")
        .trim()
        .toUpperCase();

}

function getTripIdFromUrl(){

    const queryTripId =
        new URLSearchParams(window.location.search)
            .get("viaje");

    return String(queryTripId || "").trim();

}

function getStoredDriverId(){

    return normalizeDriverId(
        new URLSearchParams(window.location.search)
            .get("driver_id")
    );

}

async function getTripById(tripId){

    if(!tripId){
        return null;
    }

    const safeTripId = String(tripId).trim();

    if(!safeTripId){
        return null;
    }

    try{
        const {
            data,
            error
        } =
            await supabaseClient
                .rpc(
                    "resolve_viaje_public",
                    {
                        p_viaje_id:
                            safeTripId
                    }
                );

        if(error){
            console.warn(
                "FLEETOPS: no fue posible resolver el viaje por UUID:",
                error
            );

            const {
                data: sessionData
            } =
                await supabaseClient.auth.getSession();

            if(!sessionData?.session){
                return null;
            }

            const fallback =
                await supabaseClient
                    .from("viajes")
                    .select(
                        "id, patente, conductor, conductor_id, empresa, empresa_id, ruta, route_id, estado, fecha_inicio, fecha_finalizacion, created_at"
                    )
                    .eq("id", safeTripId)
                    .maybeSingle();

            if(fallback.error){
                console.warn(
                    "FLEETOPS: fallback de viaje por UUID falló:",
                    fallback.error
                );
                return null;
            }

            return fallback.data || null;
        }

        if(Array.isArray(data)){
            return data[0] || null;
        }

        return data || null;
    }
    catch(error){
        console.warn(
            "FLEETOPS: resolución de viaje fallida:",
            error
        );
        return null;
    }

}

function setIdentityStatus(message){

    const status =
        document.getElementById("identityStatus");

    if(status){
        status.innerText = message;
    }

}

function getOperationConfiguration(form){

    return {
        empresa:
            form.elements["empresa"]?.value ||
            "",

        ruta:
            form.elements["ruta"]?.value ||
            ""
    };

}

async function getConductorByDriverId(driverId){

    const {
        data,
        error
    } =
        await supabaseClient
            .from("conductores")
            .select("id, nombre, driver_id")
            .eq("driver_id", driverId)
            .maybeSingle();

    if(error){
        throw new Error(
            "No fue posible resolver el Driver ID: " +
            error.message
        );
    }

    return data;

}

async function getConductorByRut(rut){

    if(!rut){
        return null;
    }

    const {
        data,
        error
    } =
        await supabaseClient
            .from("conductores")
            .select("id, nombre, driver_id, rut")
            .eq("rut", rut)
            .limit(2);

    if(error){
        throw new Error(
            "No fue posible resolver el RUT: " +
            error.message
        );
    }

    if(data && data.length > 1){
        throw new Error(
            "El RUT está asociado a más de una identidad."
        );
    }

    return data?.[0] || null;

}

async function resolveConductorIdentity({
    driverId,
    rut,
    telefono,
    conductor
}){

    if(driverId){
        const record =
            await getConductorByDriverId(
                driverId
            );

        if(!record){
            throw new Error(
                "El Driver ID no está registrado en FleetOps."
            );
        }

        return record;
    }

    const rutRecord =
        await getConductorByRut(
            rut
        );

    if(rutRecord){
        return rutRecord;
    }

    const phoneRecord =
        await getConductorByPhone(
            telefono
        );

    if(phoneRecord){
        return phoneRecord;
    }

    if(!conductor){
        throw new Error(
            "Ingresa tu Driver ID o un nombre para usar el flujo antiguo."
        );
    }

    return {
        id: null,
        driver_id: null,
        nombre: conductor
    };

}

const driverIdInput =
    fleetForm.elements["driver_id"];

const conductorInput =
    fleetForm.elements["conductor"];

try{
    const storedDriverName =
        localStorage.getItem("fleetops.driver_name");

    if(conductorInput && storedDriverName){
        conductorInput.value = storedDriverName;
        conductorInput.readOnly = true;
    }
}
catch(error){
    console.warn(
        "FLEETOPS: no fue posible recuperar el nombre local",
        error
    );
}

const initialDriverId =
    getStoredDriverId();

if(driverIdInput && initialDriverId){
    driverIdInput.value = initialDriverId;
    setIdentityStatus("IDENTIDAD CARGADA · VALIDANDO DRIVER ID...");
}

if(driverIdInput){
    driverIdInput.addEventListener("input", function(){
        if(!this.value.trim() && conductorInput){
            conductorInput.readOnly = false;
            setIdentityStatus(
                "IDENTIDAD PERSISTENTE · INGRESA TU DRIVER ID"
            );
        }
    });
}


// =====================================================
// BUSCAR CONDUCTOR POR TELÉFONO
// =====================================================

async function getConductorByPhone(telefono){

    if(!telefono){

        return null;

    }


    const {

        data,

        error

    } =
        await supabaseClient

            .from("conductores")

            .select("id, nombre, driver_id")

            .eq("telefono", telefono)

            .maybeSingle();


    if(error){

        console.error(
            "ERROR BUSCANDO CONDUCTOR:",
            error
        );

        return null;   // no bloquea el flujo

    }


    if(!data){


        return null;

    }


    return data;

}


// =====================================================
// BUSCAR VIAJE ACTIVO
// =====================================================

async function getActiveTrip(
    patente
){


    const {
        data,
        error
    } =
        await supabaseClient

            .from("viajes")

            .select(
                "id, patente, conductor, conductor_id, empresa, empresa_id, ruta, route_id, estado, fecha_inicio, fecha_finalizacion, created_at"
            )

            .eq(
                "patente",
                patente
            )

            .is(
                "fecha_finalizacion",
                null
            )

            .order(
                "created_at",
                {
                    ascending:false
                }
            )

            .limit(1);


    if(error){

        console.error(
            "ERROR BUSCANDO VIAJE:",
            error
        );

        throw new Error(
            "No fue posible buscar el viaje activo: " +
            error.message
        );

    }


    if(
        !data ||
        data.length === 0
    ){


        return null;

    }


    const trip =
        data[0];


    return trip;

}


// =====================================================
// CREAR NUEVO VIAJE
// =====================================================

async function createTrip({

    patente,
    conductor,
    conductor_id,
    empresa,
    empresa_id,
    ruta,
    route_id,
    estado,
    timestamp

}){


    const {

        data,
        error

    } =
        await supabaseClient

            .from("viajes")

            .insert([

                {

                    patente:
                        patente,

                    conductor:
                        conductor,

                    conductor_id:
                        conductor_id || null,

                    empresa:
                        empresa,

                    empresa_id:
                        empresa_id || null,

                    ruta:
                        ruta,

                    route_id:
                        route_id || null,

                    estado:
                        estado,

                    fecha_inicio:
                        timestamp,

                    fecha_finalizacion:
                        null

                }

            ])

            .select()
            .single();


    if(error){

        console.error(
            "ERROR CREANDO VIAJE:",
            error
        );

        throw new Error(
            "No fue posible crear el viaje: " +
            error.message
        );

    }


    return data;

}


// =====================================================
// OBTENER O CREAR VIAJE
// =====================================================

async function getOrCreateTrip({

    patente,
    conductor,
    conductor_id,
    empresa,
    empresa_id,
    ruta,
    route_id,
    estado,
    timestamp,
    trip_id = null,
    trip_context = null

}){

    if(trip_id || trip_context){
        const resolvedTrip =
            trip_context ||
            await getTripById(trip_id);

        if(resolvedTrip){

            return resolvedTrip;
        }
    }

    const activeTrip =
        await getActiveTrip(
            patente
        );


    if(activeTrip){

        if(
            activeTrip.conductor_id &&
            conductor_id &&
            activeTrip.conductor_id !== conductor_id
        ){
            throw new Error(
                "La patente está asignada a otro conductor."
            );
        }


        return activeTrip;

    }


    if(!empresa || !ruta){
        throw new Error(
            "Este conductor no tiene una operación asignada por la torre de control."
        );
    }


    return await createTrip({

        patente:
            patente,

        conductor:
            conductor,

        conductor_id:
            conductor_id,

        empresa:
            empresa,

        empresa_id:
            empresa_id,

        ruta:
            ruta,

        route_id:
            route_id,

        estado:
            estado,

        timestamp:
            timestamp

    });

}


// =====================================================
// CERRAR VIAJE
// =====================================================

async function finalizeTrip(
    viajeId
){


    const {

        data,
        error

    } =
        await supabaseClient

            .rpc(
                "finalizar_viaje",
                {
                    p_viaje_id:
                        viajeId
                }
            );


    if(error){

        console.error(
            "ERROR FINALIZANDO VIAJE:",
            error
        );

        throw new Error(
            "El reporte fue registrado, pero no fue posible cerrar el viaje: " +
            error.message
        );

    }


    if(!data){

        throw new Error(
            "El viaje no pudo ser finalizado."
        );

    }


    return data;

}


// =====================================================
// T-012: REPORTE DEL CONDUCTOR VÍA RPC (SIN SESIÓN)
// =====================================================

async function submitDriverReport({
    viajeId,
    estado,
    patente,
    driverId,
    rut,
    telefono,
    conductor,
    incidentCategory,
    latitud,
    longitud,
    precision,
    googleMaps,
    observacion
}){

    const toNumber = value =>
        value === "" || value === null || value === undefined
            ? null
            : Number(value);

    const {
        data,
        error
    } =
        await supabaseClient.rpc(
            "submit_driver_report",
            {
                p_viaje_id: viajeId,
                p_estado: estado,
                p_patente: patente || null,
                p_driver_id: driverId || null,
                p_rut: rut || null,
                p_telefono: telefono || null,
                p_conductor: conductor || null,
                p_incident_category: incidentCategory || null,
                p_latitud: toNumber(latitud),
                p_longitud: toNumber(longitud),
                p_precision_gps: toNumber(precision),
                p_google_maps: googleMaps || null,
                p_observacion: observacion || null
            }
        );

    if(error){
        throw new Error(
            "Supabase: " +
            error.message
        );
    }

    return Array.isArray(data)
        ? data[0] || null
        : data || null;

}

// =====================================================
// SUBMIT
// =====================================================

fleetForm.addEventListener(
    "submit",
    async function(event){

        event.preventDefault();


        const submitButton =
            fleetForm.querySelector(".send");


        submitButton.disabled =
            true;


        submitButton.innerText =
            "ENVIANDO...";


        try{


            // =========================================
            // DATOS
            // =========================================

            const conductor =
                fleetForm.elements["conductor"]
                    .value
                    .trim();


            const driverId =
                normalizeDriverId(
                    fleetForm.elements["driver_id"]
                        ? fleetForm.elements["driver_id"].value
                        : getStoredDriverId()
                );


            const rut =
                normalizeRut(
                    fleetForm.elements["rut"]
                        ? fleetForm.elements["rut"].value
                        : ""
                );


            const telefonoRaw =
                fleetForm.elements["telefono"]
                    ? fleetForm.elements["telefono"].value
                    : "";


            const telefono =
                normalizePhone(telefonoRaw);


            const patente =
                fleetForm.elements["patente"]
                    .value
                    .replace(
                        /[^a-zA-Z0-9]/g,
                        ""
                    )
                    .toUpperCase();


            const operationConfiguration =
                getOperationConfiguration(
                    fleetForm
                );

            const tripIdFromUrl =
                getTripIdFromUrl();

            const tripContext =
                tripIdFromUrl
                    ? await getTripById(tripIdFromUrl)
                    : null;

            if(tripContext){
                fleetForm.elements["empresa"].value =
                    tripContext.empresa || "";
                fleetForm.elements["ruta"].value =
                    tripContext.ruta || "";
            }

            const estado =
                fleetForm.elements["estado"]
                    .value;


            const observacion =
                fleetForm.elements["observacion"]
                    .value
                    .trim();


            const latitud =
                fleetForm.elements["latitud"]
                    .value;


            const longitud =
                fleetForm.elements["longitud"]
                    .value;


            const precision =
                fleetForm.elements["precision"]
                    .value;


            const googleMaps =
                fleetForm.elements["maps"]
                    .value;


            const incidentCategory =
                fleetForm.elements["incident_category"]?.value || null;


            // =========================================
            // VALIDACIÓN
            // =========================================

            if(!estado){

                alert(
                    "Selecciona un estado operacional."
                );


                submitButton.disabled =
                    false;


                submitButton.innerText =
                    "ENVIAR ACTUALIZACIÓN";


                return;

            }

            if(estado === "Incidente" && !incidentCategory){
                alert("Selecciona la causa del incidente.");
                submitButton.disabled = false;
                submitButton.innerText = "ENVIAR ACTUALIZACIÓN";
                return;
            }


            if(!patente){

                alert(
                    "Ingresa una patente válida."
                );


                submitButton.disabled =
                    false;


                submitButton.innerText =
                    "ENVIAR ACTUALIZACIÓN";


                return;

            }


            // =========================================
            // T-012: FLUJO QR (?viaje=UUID) VÍA RPC VALIDADA
            // =========================================
            // Desde T-012 el rol anónimo no puede leer
            // conductores ni insertar en reportes. El reporte
            // del conductor se envía a submit_driver_report,
            // que valida viaje activo, patente y que el
            // conductor pertenezca a la organización del viaje.
            // =========================================

            if(tripIdFromUrl){

                const submitted =
                    await submitDriverReport({
                        viajeId: tripIdFromUrl,
                        estado,
                        patente,
                        driverId,
                        rut,
                        telefono,
                        conductor,
                        incidentCategory:
                            estado === "Incidente"
                                ? incidentCategory
                                : null,
                        latitud,
                        longitud,
                        precision,
                        googleMaps,
                        observacion
                    });

                try{
                    if(submitted?.conductor){
                        localStorage.setItem("fleetops.driver_name", submitted.conductor);
                    }
                }
                catch(storageError){
                    console.warn("FLEETOPS: no fue posible guardar identidad local", storageError);
                }

                window.location.replace(
                    "success.html?viaje=" +
                    encodeURIComponent(tripIdFromUrl)
                );

                return;

            }

            const {
                data: sessionData
            } =
                await supabaseClient.auth.getSession();

            if(!sessionData?.session){
                throw new Error(
                    "Escanea el QR del viaje entregado por la torre de control para reportar."
                );
            }

            // =========================================
            // IDENTIFICAR CONDUCTOR
            // =========================================

            const conductorRecord =
                await resolveConductorIdentity({
                    driverId:
                        driverId,

                    rut:
                        rut,

                    telefono:
                        telefono,

                    conductor:
                        conductor
                });


            const conductor_id =
                conductorRecord?.id || null;

            const resolvedConductor =
                conductorRecord?.nombre ||
                conductor;

            if(driverIdInput && driverId){
                driverIdInput.value =
                    conductorRecord.driver_id ||
                    driverId;
            }

            if(conductorInput && conductorRecord?.nombre){
                conductorInput.value =
                    conductorRecord.nombre;
                conductorInput.readOnly = true;
            }

            setIdentityStatus(
                conductor_id
                    ? "IDENTIDAD RESUELTA · OPERACIÓN ASOCIADA"
                    : "MODO LEGACY · IDENTIDAD SIN conductor_id"
            );


            // =========================================
            // OBTENER / CREAR VIAJE
            // =========================================

            const trip =
                await getOrCreateTrip({

                    patente:
                        patente,

                    conductor:
                        resolvedConductor,

                    conductor_id:
                        conductor_id,

                    empresa:
                        tripContext?.empresa ||
                        operationConfiguration.empresa,

                    empresa_id:
                        tripContext?.empresa_id || null,

                    ruta:
                        tripContext?.ruta ||
                        operationConfiguration.ruta,

                    route_id:
                        tripContext?.route_id || null,

                    estado:
                        estado,

                    timestamp:
                        new Date().toISOString(),

                    trip_id:
                        tripContext?.id ||
                        tripIdFromUrl ||
                        null,

                    trip_context:
                        tripContext

                });


            const viajeId =
                trip.id;


            // =========================================
            // REPORTE
            // =========================================

            const report = {

                conductor:
                    resolvedConductor,

                conductor_id:
                    conductor_id || null,

                patente:
                    patente,

                empresa:
                    trip.empresa ||
                    operationConfiguration.empresa,

                ruta:
                    trip.ruta ||
                    operationConfiguration.ruta,

                estado:
                    estado,

                incident_category:
                    estado === "Incidente"
                        ? incidentCategory
                        : null,

                latitud:
                    latitud
                    ? Number(latitud)
                    : null,

                longitud:
                    longitud
                    ? Number(longitud)
                    : null,

                precision_gps:
                    precision
                    ? Number(precision)
                    : null,

                google_maps:
                    googleMaps ||
                    null,

                observacion:
                    observacion ||
                    null,

                viaje_id:
                    viajeId

            };


            // =========================================
            // INSERTAR REPORTE
            // =========================================


            const {

                data,

                error

            } =
                await supabaseClient

                    .from("reportes")

                    .insert([
                        report
                    ])

                    .select();


            if(error){

                throw new Error(
                    "Supabase: " +
                    error.message
                );

            }


            // =========================================
            // FINALIZACIÓN
            // =========================================
            // La finalización real requiere autorización de torre.
            // El flujo público no debe cerrar un viaje arbitrariamente.
            // =========================================

            if(
                estado ===
                "Finalizado" &&
                !tripIdFromUrl
            ){

                console.warn(
                    "FLEETOPS: el viaje no se finaliza automáticamente; la torre debe autorizarlo."
                );

            }


            // =========================================
            // SUCCESS
            // =========================================


            window.location.replace(
                "success.html"
            );

        }


        catch(error){

            console.error(
                "ERROR FLEETOPS:",
                error
            );


            alert(
                "No fue posible enviar el reporte.\n\n" +
                error.message
            );


            submitButton.disabled =
                false;


            submitButton.innerText =
                "ENVIAR ACTUALIZACIÓN";

        }

    }
);
