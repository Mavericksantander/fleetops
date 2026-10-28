
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

    const queryDriverId =
        new URLSearchParams(window.location.search)
            .get("driver_id");

    if(queryDriverId){
        return normalizeDriverId(queryDriverId);
    }

    try{
        return normalizeDriverId(
            localStorage.getItem("fleetops.driver_id")
        );
    }
    catch(error){
        return "";
    }

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


            if(!tripIdFromUrl){
                throw new Error(
                    "Escanea el QR del viaje entregado por la torre de control para reportar."
                );
            }

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
                if(submitted?.driver_id){
                    localStorage.setItem("fleetops.driver_id", submitted.driver_id);
                }
                if(submitted?.conductor){
                    localStorage.setItem("fleetops.driver_name", submitted.conductor);
                }
            }
            catch(storageError){
                console.warn("FLEETOPS: no fue posible guardar identidad local", storageError);
            }

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
