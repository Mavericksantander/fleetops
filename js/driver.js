// =====================================================
// PRÆTOR FleetOps · Driver Onboarding
// =====================================================

// =====================================================
// ELEMENTOS
// =====================================================

const driverForm =
    document.getElementById("driverForm");

const successScreen =
    document.getElementById("successScreen");

const recoverDriverButton =
    document.getElementById("recoverDriverButton");

const inviteStatus =
    document.getElementById("inviteStatus");

const inviteToken =
    new URLSearchParams(window.location.search).get("invite")?.trim() || "";

const onboardingSteps =
    [...document.querySelectorAll(".onboarding-step")];

let currentStep = 1;

let inviteOrganizationId = null;
let inviteOrganizationName = null;

async function validateInvite() {
    if (!inviteToken) {
        inviteStatus.innerText = "Esta página requiere un enlace de invitación válido.";
        driverForm.querySelectorAll("input, select, button").forEach(function (element) {
            element.disabled = true;
        });
        return;
    }

    const { data, error } = await supabaseClient.rpc(
        "resolve_organization_driver_invite",
        { p_token: inviteToken }
    );

    if (error || !data?.[0]) {
        inviteStatus.innerText = error?.message || "La invitación no es válida o expiró.";
        driverForm.querySelectorAll("input, select, button").forEach(function (element) {
            element.disabled = true;
        });
        return;
    }

    inviteOrganizationId = data[0].organization_id;
    inviteOrganizationName = data[0].organization_name;
    inviteStatus.innerText = `Solicitud para ${inviteOrganizationName}`;
}


if (!driverForm) {

    console.error(
        "driver.js: #driverForm no encontrado."
    );

    throw new Error(
        "FleetOps Driver: formulario no encontrado."
    );

}

validateInvite().catch(function (error) {
    console.error("DRIVER INVITE ERROR:", error);
    inviteStatus.innerText = "No fue posible validar la invitación.";
});

function showStep(stepNumber) {

    currentStep = stepNumber;

    onboardingSteps.forEach(function (step) {
        const isActive =
            Number(step.dataset.step) === stepNumber;

        step.hidden = !isActive;
        step.classList.toggle("active", isActive);
    });

    document.querySelectorAll("[data-step-indicator]").forEach(function (indicator) {
        indicator.classList.toggle(
            "active",
            Number(indicator.dataset.stepIndicator) === stepNumber
        );
    });

}

function validateCurrentStep() {

    const currentSection =
        driverForm.querySelector(`[data-step="${currentStep}"]`);

    if (!currentSection) {
        return true;
    }

    const requiredFields =
        [...currentSection.querySelectorAll("[required]")];

    return requiredFields.every(function (field) {
        if (!field.value.trim()) {
            field.reportValidity();
            return false;
        }

        return true;
    });

}

document.querySelectorAll(".next-step").forEach(function (button) {
    button.addEventListener("click", function () {
        const step = Number(button.closest("[data-step]")?.dataset.step);

        if (step === 2 && !(capturedPhotos.frente && capturedPhotos.reverso && capturedPhotos.selfie)) {
            return;
        }

        if (validateCurrentStep() && currentStep < onboardingSteps.length) {
            showStep(currentStep + 1);
        }
    });
});

document.querySelectorAll(".back-step").forEach(function (button) {
    button.addEventListener("click", function () {
        if (currentStep > 1) {
            showStep(currentStep - 1);
        }
    });
});

const cameraPanel =
    document.getElementById("cameraPanel");

const cameraSelect =
    document.getElementById("cameraSelect");

const cameraPreview =
    document.getElementById("cameraPreview");

const cameraCanvas =
    document.getElementById("cameraCanvas");

const takePhotoButton =
    document.getElementById("takePhoto");

const closeCameraButton =
    document.getElementById("closeCamera");

let cameraStream = null;
let activeCameraSide = null;

const capturedPhotos = {
    frente: null,
    reverso: null,
    selfie: null
};

const licenseContinueButton =
    document.querySelector('[data-step="2"] .next-step');

function refreshLicenseContinue() {
    if (!licenseContinueButton) {
        return;
    }

    licenseContinueButton.disabled = !(
        capturedPhotos.frente &&
        capturedPhotos.reverso &&
        capturedPhotos.selfie
    );
}

refreshLicenseContinue();

async function loadCameraDevices() {

    const devices =
        await navigator.mediaDevices.enumerateDevices();

    const cameras =
        devices.filter(function (device) {
            return device.kind === "videoinput";
        });

    cameraSelect.replaceChildren();

    cameras.forEach(function (camera, index) {
        const option = document.createElement("option");
        option.value = camera.deviceId;
        option.textContent = camera.label || ("Cámara " + (index + 1));
        cameraSelect.appendChild(option);
    });

    return cameras;

}

async function openCamera(side) {

    if (!navigator.mediaDevices?.getUserMedia) {
        alert("La cámara no está disponible en este navegador.");
        return;
    }

    activeCameraSide = side;
    cameraPanel.hidden = false;

    if (cameraStream) {
        cameraStream.getTracks().forEach(function (track) {
            track.stop();
        });
    }

    cameraStream =
        await navigator.mediaDevices.getUserMedia({
            video: {
                deviceId: cameraSelect.value
                    ? { exact: cameraSelect.value }
                    : undefined,
                facingMode: "environment"
            },
            audio: false
        });

    cameraPreview.srcObject = cameraStream;
    cameraPreview.classList.add("active");

    await loadCameraDevices();

}

function closeCamera() {

    if (cameraStream) {
        cameraStream.getTracks().forEach(function (track) {
            track.stop();
        });
        cameraStream = null;
    }

    cameraPreview.srcObject = null;
    cameraPreview.classList.remove("active");
    cameraPanel.hidden = true;
    activeCameraSide = null;

}

document.querySelectorAll(".start-camera").forEach(function (button) {
    button.addEventListener("click", async function () {
        const capture =
            this.closest("[data-camera-side]");

        try {
            await openCamera(capture.dataset.cameraSide);
        }
        catch (error) {
            console.error("DRIVER CAMERA ERROR:", error);
            closeCamera();
            alert("No fue posible abrir la cámara.");
        }
    });
});

cameraSelect.addEventListener("change", async function () {
    if (activeCameraSide) {
        try {
            await openCamera(activeCameraSide);
        }
        catch (error) {
            console.error("DRIVER CAMERA SWITCH ERROR:", error);
        }
    }
});

takePhotoButton.addEventListener("click", function () {

    if (!cameraStream || !activeCameraSide) {
        return;
    }

    cameraCanvas.width = cameraPreview.videoWidth;
    cameraCanvas.height = cameraPreview.videoHeight;
    cameraCanvas.getContext("2d").drawImage(
        cameraPreview,
        0,
        0,
        cameraCanvas.width,
        cameraCanvas.height
    );

    const sideContainer =
        document.querySelector(`[data-camera-side="${activeCameraSide}"]`);

    const preview =
        sideContainer.querySelector(".photo-preview");

    const photoDataUrl =
        cameraCanvas.toDataURL("image/jpeg", 0.9);

    preview.src = photoDataUrl;
    preview.classList.add("active");

    cameraCanvas.toBlob(function (blob) {
        if (!blob) {
            alert("No fue posible procesar la fotografía.");
            return;
        }

        capturedPhotos[activeCameraSide] = blob;
        refreshLicenseContinue();

        closeCamera();
    }, "image/jpeg", 0.9);

});

closeCameraButton.addEventListener("click", closeCamera);


// =====================================================
// NORMALIZADORES
// =====================================================

function normalizePlate(value) {
  return String(value || "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

function normalizePhone(value) {

    return String(value || "")
        .replace(/[^\d]/g, "");

}

function normalizeRut(value) {

    return String(value || "")
        .replace(/[^0-9kK]/g, "")
        .toUpperCase();

}

if (recoverDriverButton) {
    recoverDriverButton.addEventListener("click", async function () {
        alert("La recuperación requiere una invitación de la empresa.");
    });
}


async function sha256Hex(value) {
  const encoded = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", encoded);

  return Array.from(new Uint8Array(digest), function (byte) {
    return byte.toString(16).padStart(2, "0");
  }).join("");
}

const ALLOWED_DOCUMENT_TYPES = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  heic: "image/heic",
  heif: "image/heif",
  pdf: "application/pdf"
};

const ALLOWED_DOCUMENT_MIME = new Set(Object.values(ALLOWED_DOCUMENT_TYPES));

function allowlistedContentType(file) {
  let type = String(file.type || "").toLowerCase();

  if (type === "image/jpg") {
    type = "image/jpeg";
  }

  if (ALLOWED_DOCUMENT_MIME.has(type)) {
    return type;
  }

  const extension = String(file.name || "").toLowerCase().split(".").pop();
  const mapped = ALLOWED_DOCUMENT_TYPES[extension];

  if (mapped) {
    return mapped;
  }

  throw new Error("El archivo debe ser JPEG, PNG, WEBP, GIF, HEIC, HEIF o PDF.");
}

async function uploadDocument(file, storagePath) {
  if (!file) {
    throw new Error("Archivo requerido.");
  }

  const contentType = allowlistedContentType(file);

  const { error } = await supabaseClient.storage
    .from("fleetops-documents")
    .upload(storagePath, file, {
      contentType
    });

  if (error) {
    const denied = /row-level security|unauthorized/i.test(error.message || "");
    throw new Error(
      denied
        ? "La invitación no permite subir documentos. Pide un enlace nuevo."
        : `No se pudo subir ${file.name}: ${error.message}`
    );
  }

  return contentType;
}

// =====================================================
// SUBMIT
// =====================================================

driverForm.addEventListener(
    "submit",
    async function (event) {

        event.preventDefault();


        const btn =
            driverForm.querySelector('[data-step="3"] .send');


        btn.disabled = true;

        btn.innerText = "REGISTRANDO...";

        let uploadedStoragePaths = [];

        try {

            const nombre =
                driverForm.elements["nombre"]
                    .value
                    .trim();


            const rut =
                normalizeRut(
                    driverForm.elements["rut"]
                        .value
                );


            const telefono =
                normalizePhone(
                    driverForm.elements["telefono"]
                        .value
                );


            const tipo_licencia =
                driverForm.elements["tipo_licencia"]
                    .value;


            const ciudad =
                driverForm.elements["ciudad"]
                    .value
                    .trim();


            const patente_habitual =
                normalizePlate(
                    driverForm.elements["patente_habitual"]
                        .value
                );


            const licencia =
                driverForm.elements["licencia"]
                    .value
                    .trim();


            const licencia_vencimiento =
                driverForm.elements["licencia_vencimiento"]
                    .value;


            const permiso_circulacion =
                driverForm.elements["permiso_circulacion"]
                    .files?.[0] || null;


            const soap =
                driverForm.elements["soap"]
                    .files?.[0] || null;


            const revision_tecnica =
                driverForm.elements["revision_tecnica"]
                    .files?.[0] || null;


            const padron =
                driverForm.elements["padron"]
                    .files?.[0] || null;


            // =========================================
            // VALIDACIÓN
            // =========================================

            if (
                !nombre ||
                !rut ||
                telefono.length < 8 ||
                !tipo_licencia ||
                !ciudad ||
                !licencia ||
                !licencia_vencimiento ||
                !patente_habitual ||
                !capturedPhotos.frente ||
                !capturedPhotos.reverso ||
                !capturedPhotos.selfie ||
                !permiso_circulacion ||
                !soap ||
                !revision_tecnica ||
                !padron
            ) {

                throw new Error(
                    "Completa todos los campos obligatorios."
                );

            }


            // =========================================
            // BUSCAR EXISTENTE
            // =========================================

            const equipmentDocuments = [
                {
                    tipoDocumento: "permiso_circulacion",
                    file: permiso_circulacion,
                    folder: "permiso-circulacion"
                },
                {
                    tipoDocumento: "soap",
                    file: soap,
                    folder: "soap"
                },
                {
                    tipoDocumento: "revision_tecnica",
                    file: revision_tecnica,
                    folder: "revision-tecnica"
                },
                {
                    tipoDocumento: "padron_vehicular",
                    file: padron,
                    folder: "padron"
                }
            ];

            const onboardingPrefix =
                "onboarding/" + await sha256Hex(inviteToken);
            const tractoDocumentMetadata = [];

            for (const document of equipmentDocuments) {
                const rawExtension =
                    document.file.name.includes(".")
                        ? document.file.name.split(".").pop().toLowerCase()
                        : "bin";
                const extension =
                    /^[a-z0-9]+$/.test(rawExtension)
                        ? rawExtension
                        : "bin";

                const storagePath =
                    `${onboardingPrefix}/equipment/${document.folder}/${crypto.randomUUID()}.${extension}`;

                const contentType = await uploadDocument(
                    document.file,
                    storagePath
                );
                uploadedStoragePaths.push(storagePath);
                tractoDocumentMetadata.push({
                    tipo_documento: document.tipoDocumento,
                    storage_path: storagePath,
                    nombre_archivo: document.file.name,
                    mime_type: contentType,
                    tamano_bytes: document.file.size
                });
            }

            const driverDocuments = [
                {
                    tipoDocumento: "licencia_frente",
                    blob: capturedPhotos.frente,
                    folder: "frente"
                },
                {
                    tipoDocumento: "licencia_reverso",
                    blob: capturedPhotos.reverso,
                    folder: "reverso"
                },
                {
                    tipoDocumento: "selfie",
                    blob: capturedPhotos.selfie,
                    folder: "selfie"
                }
            ];

            const conductorDocumentMetadata = [];

            for (const document of driverDocuments) {
                const file = new File(
                    [document.blob],
                    `${document.tipoDocumento}.jpg`,
                    {
                        type: document.blob.type || "image/jpeg"
                    }
                );

                const storagePath =
                    `${onboardingPrefix}/drivers/${document.folder}/${crypto.randomUUID()}.jpg`;

                const contentType = await uploadDocument(
                    file,
                    storagePath
                );
                uploadedStoragePaths.push(storagePath);
                conductorDocumentMetadata.push({
                    tipo_documento: document.tipoDocumento,
                    storage_path: storagePath,
                    nombre_archivo: file.name,
                    mime_type: contentType,
                    tamano_bytes: file.size
                });
            }

            const { data: onboarding, error: onboardingError } =
                await supabaseClient.rpc("complete_organization_driver_onboarding", {
                    p_token: inviteToken,
                    p_nombre: nombre,
                    p_rut: rut,
                    p_telefono: telefono,
                    p_ciudad: ciudad,
                    p_tipo_licencia: tipo_licencia,
                    p_licencia: licencia,
                    p_licencia_vencimiento: licencia_vencimiento,
                    p_patente: patente_habitual,
                    p_conductor_documents: conductorDocumentMetadata,
                    p_tracto_documents: tractoDocumentMetadata
                });

            if (onboardingError || !onboarding?.[0]) {
                throw new Error(
                    onboardingError?.message ||
                    "No fue posible completar el onboarding."
                );
            }

            const conductorDriverId = onboarding[0].driver_id;

            showSuccess(
                conductorDriverId,
                nombre,
                false
            );

        }


        catch (err) {

            console.error(
                "DRIVER ERROR:",
                err
            );

            if (uploadedStoragePaths.length) {
                const { error: cleanupError } = await supabaseClient.storage
                    .from("fleetops-documents")
                    .remove(uploadedStoragePaths);

                if (cleanupError) {
                    console.error("DRIVER STORAGE CLEANUP ERROR:", cleanupError);
                }
            }

            alert(
                "No fue posible crear el perfil.\n\n" +
                err.message
            );


            btn.disabled = false;

            btn.innerText = "CONFIRMAR IDENTIDAD";

        }

    }
);


// =====================================================
// PANTALLA DE ÉXITO
// =====================================================

function showSuccess(
    driverId,
    nombre,
    existed
) {

    const operationLink =
        document.getElementById("operationBtn");

    if (operationLink) {
        const viaje =
            new URLSearchParams(window.location.search).get("viaje")?.trim() || "";

        if (!viaje) {
            operationLink.hidden = true;
            operationLink.removeAttribute("href");
        } else {
            operationLink.hidden = false;
            operationLink.href =
                "reportes.html?viaje=" + encodeURIComponent(viaje);
        }
    }

    driverForm.style.display = "none";

    successScreen.style.display = "block";


    document.getElementById("driverIdMsg").innerText =
        existed
            ? "YA TENÍAS PERFIL · TU DRIVER ID"
            :             `SOLICITUD ENVIADA · ${inviteOrganizationName || "ORGANIZACIÓN"}`;


    document.getElementById("driverIdValue").innerText =
        driverId;


    document.getElementById("driverIdName").innerText =
        nombre;


    successScreen.scrollIntoView({
        behavior: "smooth"
    });

}


// =====================================================
// COPIAR ID
// =====================================================

document
    .getElementById("copyBtn")
    .addEventListener(
        "click",
        function () {

            const id =
                document.getElementById(
                    "driverIdValue"
                ).innerText;


            const btn = this;


            navigator.clipboard
                .writeText(id)
                .then(
                    () => {

                        btn.innerText =
                            "COPIADO ✓";


                        setTimeout(
                            () => {

                                btn.innerText =
                                    "COPIAR ID";

                            },
                            1500
                        );

                    }
                );

        }
    );