/**
 * Configuración de producción.
 *
 * La `publishableKey` (antes anon key) está diseñada para viajar en el cliente:
 * no otorga ningún permiso por sí sola. Toda la autorización real vive en las
 * políticas RLS y en las funciones SECURITY DEFINER de Postgres.
 *
 * La `service_role` / secret key NUNCA debe aparecer en este proyecto.
 */
export const environment = {
  produccion: true,
  supabaseUrl: 'https://bjqinqcnnvofdmhqwiwt.supabase.co',
  supabaseKey: 'sb_publishable_ARI3tuZ7EcCXr_-odRLfQQ_S_2JL3mz',
  clinica: {
    nombre: 'NeoTerapia',
    telefono: '',
    whatsapp: '',
    direccion: '',
  },
};
