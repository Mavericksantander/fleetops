const supabaseConfig = window.FLEETOPS_SUPABASE_CONFIG;

if (!supabaseConfig?.url || !supabaseConfig?.anonKey) {
  throw new Error(
    "Falta la configuración de Supabase. Crea js/supabase-config.js a partir de js/supabase-config.example.js."
  );
}

const supabaseClient = supabase.createClient(
  supabaseConfig.url,
  supabaseConfig.anonKey
);