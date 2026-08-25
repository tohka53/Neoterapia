/**
 * Tipos del dominio. Reflejan el esquema de Supabase.
 *
 * Regla que atraviesa todo el archivo: el paciente NO es un usuario. No existe
 * `PacienteSesion`, `LoginPaciente` ni nada parecido. Lo único que el paciente
 * recibe es un `codigo_referencia` y, opcionalmente, enlaces de un solo uso.
 */

export type RolUsuario = 'superadmin' | 'admin' | 'recepcion' | 'fisioterapeuta';

export type EstadoCita =
  | 'solicitada' | 'confirmada' | 'reprogramada'
  | 'rechazada' | 'cancelada' | 'atendida' | 'ausente';

export type OrigenCita = 'publico' | 'telefono' | 'whatsapp' | 'presencial' | 'interno';
export type CanalContacto = 'email' | 'whatsapp' | 'telefono';
export type TipoDocumento = 'dpi' | 'pasaporte' | 'otro';
export type EstadoPaciente = 'activo' | 'inactivo' | 'fusionado';
export type VistaCuerpo = 'anterior' | 'posterior';
export type LadoCuerpo = 'izquierdo' | 'derecho' | 'central';
export type RegionCuerpo =
  | 'cabeza_cuello' | 'miembro_superior' | 'tronco' | 'columna' | 'miembro_inferior';
export type MetodoPago = 'efectivo' | 'tarjeta' | 'transferencia' | 'deposito' | 'otro';
export type EstadoPago = 'pendiente' | 'pagado' | 'anulado' | 'reembolsado';
export type TipoAlerta =
  | 'nombre_no_coincide' | 'posible_duplicado' | 'dpi_sospechoso'
  | 'contacto_cambiado' | 'solicitud_sospechosa';

export interface Perfil {
  id: string;
  nombre_completo: string;
  rol: RolUsuario;
  email: string | null;
  telefono: string | null;
  colegiado: string | null;
  especialidad: string | null;
  color_agenda: string;
  activo: boolean;
  /**
   * Pasa consulta. Es independiente del rol: un superadministrador que atiende
   * aparece en la agenda y firma notas; un fisioterapeuta lo tiene siempre.
   */
  atiende: boolean;
}

export interface AreaCuerpo {
  codigo: string;
  nombre: string;
  region: RegionCuerpo;
  lado: LadoCuerpo;
  vista: VistaCuerpo;
  svg_x: number;
  svg_y: number;
  orden: number;
}

/** Área seleccionada por el paciente o registrada en una sesión. */
export interface AreaMarcada {
  codigo: string;
  nombre?: string;
  vista?: VistaCuerpo;
  svg_x?: number;
  svg_y?: number;
  intensidad?: number | null;
  nivel_dolor?: number | null;
  movilidad?: 'normal' | 'limitada' | 'muy_limitada' | null;
  inflamacion?: boolean;
  nota?: string | null;
  observacion?: string | null;
}

export interface Slot {
  hora: string;
  inicio: string;
  cupos_totales: number;
  cupos_ocupados: number;
  disponible: boolean;
}

/** Lo que el formulario público manda a `solicitar_cita`. */
export interface SolicitudCita {
  dpi: string;
  tipo_documento?: TipoDocumento;
  nombre_completo: string;
  telefono?: string | null;
  whatsapp?: string | null;
  email?: string | null;
  canal_preferido: CanalContacto;
  fecha: string;
  hora?: string | null;
  franja?: 'manana' | 'tarde' | 'indistinto';
  motivo_consulta?: string | null;
  comentarios?: string | null;
  es_primera_vez?: boolean;
  acepta_politica: boolean;
  areas: Array<{ codigo: string; intensidad?: number; nota?: string }>;
}

export interface RespuestaSolicitud {
  ok: boolean;
  duplicada?: boolean;
  codigo_referencia?: string;
  estado?: EstadoCita;
  fecha_solicitada?: string;
  canal?: CanalContacto;
  mensaje?: string;
  error?: string;
  motivo?: string;
}

export interface CitaListado {
  id: string;
  codigo_referencia: string;
  estado: EstadoCita;
  origen: OrigenCita;
  fecha_solicitada: string;
  hora_solicitada: string | null;
  franja_solicitada: string | null;
  inicio_programado: string | null;
  fin_programado: string | null;
  consultorio: string | null;
  motivo_consulta: string | null;
  comentarios_paciente: string | null;
  es_primera_vez: boolean;
  nombre_declarado: string;
  telefono_declarado: string | null;
  whatsapp_declarado: string | null;
  email_declarado: string | null;
  canal_preferido: CanalContacto;
  motivo_estado: string | null;
  creado_en: string;
  paciente_id: string;
  nombre_completo: string;
  dpi_mascara: string;
  estado_paciente: EstadoPaciente;
  fisioterapeuta_id: string | null;
  fisioterapeuta: string | null;
  color_agenda: string | null;
  areas: AreaMarcada[];
  alertas_pendientes: number;
}

export interface PacienteListado {
  id: string;
  nombre_completo: string;
  dpi_mascara: string;
  tipo_documento: TipoDocumento;
  dpi_valido: boolean;
  telefono: string | null;
  whatsapp: string | null;
  email: string | null;
  canal_preferido: CanalContacto;
  estado: EstadoPaciente;
  fecha_nacimiento: string | null;
  edad: number | null;
  fisioterapeuta_id: string | null;
  fisioterapeuta: string | null;
  creado_en: string;
  alta_automatica: boolean;
  citas_totales: number;
  ultima_visita: string | null;
  proxima_cita: string | null;
  ausencias: number;
  alertas_pendientes: number;
}

export interface EventoAgenda {
  id: string;
  codigo_referencia: string;
  inicio: string;
  fin: string;
  estado: EstadoCita;
  consultorio: string | null;
  paciente_id: string;
  paciente: string;
  dpi_mascara: string;
  telefono: string | null;
  fisioterapeuta_id: string | null;
  fisioterapeuta: string | null;
  color: string;
  motivo_consulta: string | null;
  es_primera_vez: boolean;
  sesion_id: string | null;
  firmada_en: string | null;
}

export interface Sesion {
  id: string;
  cita_id: string;
  paciente_id: string;
  fisioterapeuta_id: string;
  inicio: string;
  fin: string | null;
  dolor_inicial: number | null;
  dolor_final: number | null;
  subjetivo: string | null;
  objetivo: string | null;
  analisis: string | null;
  plan: string | null;
  recomendaciones: string | null;
  observaciones: string | null;
  requiere_seguimiento: boolean;
  proxima_sugerida: string | null;
  firmada_en: string | null;
}

export interface SesionDetalle extends Sesion {
  codigo_referencia: string;
  inicio_programado: string | null;
  paciente: string;
  dpi_mascara: string;
  fisioterapeuta: string;
  tratamientos: TratamientoAplicado[];
  areas: AreaMarcada[];
  total_tratamientos: number;
}

/** Sin precio: varía por caso y se escribe al aplicarlo en la sesión. */
export interface Tratamiento {
  id: string;
  codigo: string;
  nombre: string;
  descripcion: string | null;
  duracion_min: number;
  requiere_nota: boolean;
  activo: boolean;
}

export interface TratamientoAplicado {
  id: string;
  codigo: string;
  nombre: string;
  cantidad: number;
  precio: number;
  notas: string | null;
}

export interface Pago {
  id: string;
  paciente_id: string;
  cita_id: string | null;
  sesion_id: string | null;
  monto: number;
  moneda: string;
  metodo: MetodoPago;
  estado: EstadoPago;
  referencia: string | null;
  descripcion: string | null;
  fecha: string;
  registrado_por: string | null;
  motivo_anulacion: string | null;
}

export interface Alerta {
  id: string;
  tipo: TipoAlerta;
  severidad: 1 | 2 | 3;
  paciente_id: string | null;
  cita_id: string | null;
  titulo: string;
  detalle: Record<string, unknown>;
  estado: 'pendiente' | 'revisada' | 'descartada';
  nota_revision: string | null;
  creado_en: string;
}

export interface Duplicado {
  id: string;
  motivo: string;
  puntaje: number;
  estado: 'pendiente' | 'descartado' | 'fusionado';
  creado_en: string;
  a_id: string; a_nombre: string; a_dpi: string;
  a_telefono: string | null; a_email: string | null; a_creado: string; a_citas: number;
  b_id: string; b_nombre: string; b_dpi: string;
  b_telefono: string | null; b_email: string | null; b_creado: string; b_citas: number;
}

export interface RegistroAuditoria {
  id: number;
  ocurrido_en: string;
  actor_id: string | null;
  actor_rol: RolUsuario | null;
  actor_email: string | null;
  accion: string;
  entidad: string;
  entidad_id: string | null;
  paciente_id: string | null;
  descripcion: string | null;
  ip: string | null;
}

export interface Mensaje {
  id: string;
  cita_id: string | null;
  paciente_id: string | null;
  canal: 'email' | 'whatsapp';
  tipo: string;
  destinatario: string;
  asunto: string | null;
  cuerpo: string;
  estado: 'pendiente' | 'enviado' | 'fallido' | 'omitido' | 'cancelado';
  creado_en: string;
}

export interface MetricasTablero {
  solicitudes_pendientes: number;
  citas_hoy: number;
  citas_semana: number;
  alertas_pendientes: number;
  duplicados_pendientes: number;
  pacientes_activos: number;
  sesiones_sin_firmar: number;
  mensajes_en_cola: number;
}

/** Un mapa corporal completo en un instante: la solicitud o una sesión. */
export interface MomentoMapa {
  momento_id: string;
  momento_tipo: 'solicitud' | 'sesion';
  fecha: string;
  etiqueta: string;
  firmada: boolean | null;
  responsable: string | null;
  dolor_promedio: number | null;
  dolor_maximo: number | null;
  areas: AreaMarcada[];
}

export interface PuntoEvolucion {
  area_codigo: string;
  area_nombre: string;
  vista: VistaCuerpo;
  svg_x: number;
  svg_y: number;
  fecha: string;
  nivel_dolor: number;
  origen: 'sesion' | 'solicitud';
}

export const ETIQUETAS_ESTADO: Record<EstadoCita, string> = {
  solicitada: 'Solicitada',
  confirmada: 'Confirmada',
  reprogramada: 'Reprogramada',
  rechazada: 'Rechazada',
  cancelada: 'Cancelada',
  atendida: 'Atendida',
  ausente: 'No asistió',
};

export const ETIQUETAS_ROL: Record<RolUsuario, string> = {
  superadmin: 'Superadministrador',
  admin: 'Administrador',
  recepcion: 'Responsable de citas',
  fisioterapeuta: 'Fisioterapeuta',
};

export const ETIQUETAS_ALERTA: Record<TipoAlerta, string> = {
  nombre_no_coincide: 'Nombre no coincide con el DPI',
  posible_duplicado: 'Posible ficha duplicada',
  dpi_sospechoso: 'DPI sospechoso',
  contacto_cambiado: 'Contacto distinto al de la ficha',
  solicitud_sospechosa: 'Solicitud sospechosa',
};


// ---------------------------------------------------------------------------
// Inventario
// ---------------------------------------------------------------------------

export type CategoriaArticulo =
  | 'insumo' | 'equipo' | 'medicamento' | 'limpieza' | 'papeleria' | 'otro';

export type TipoMovimiento = 'entrada' | 'salida' | 'merma' | 'ajuste';

export interface ArticuloInventario {
  id: string;
  codigo: string;
  nombre: string;
  descripcion: string | null;
  categoria: CategoriaArticulo;
  unidad: string;
  /** La calcula el trigger de movimientos; nunca se edita a mano. */
  existencia: number;
  minimo: number;
  ubicacion: string | null;
  activo: boolean;
  creado_en: string;
  bajo_minimo: boolean;
  agotado: boolean;
  ultimo_movimiento: string | null;
  ultimo_tipo: TipoMovimiento | null;
  creado_por_nombre: string | null;
}

export interface MovimientoInventario {
  id: string;
  articulo_id: string;
  tipo: TipoMovimiento;
  cantidad: number;
  existencia_anterior: number;
  existencia_resultante: number;
  motivo: string | null;
  referencia: string | null;
  creado_en: string;
  articulo_codigo: string;
  articulo_nombre: string;
  unidad: string;
  responsable: string | null;
}

export const ETIQUETAS_CATEGORIA: Record<CategoriaArticulo, string> = {
  insumo: 'Insumo',
  equipo: 'Equipo',
  medicamento: 'Medicamento',
  limpieza: 'Limpieza',
  papeleria: 'Papelería',
  otro: 'Otro',
};

export const ETIQUETAS_MOVIMIENTO: Record<TipoMovimiento, string> = {
  entrada: 'Entrada',
  salida: 'Salida',
  merma: 'Merma',
  ajuste: 'Ajuste por conteo',
};
