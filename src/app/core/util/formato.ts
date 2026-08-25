/** Utilidades de formato y validación del lado cliente.
 *  La validación *real* siempre vuelve a hacerse en Postgres. */

const TZ = 'America/Guatemala';

/** Municipios por departamento (índice 1..22), con la misma holgura del backend. */
const MUNICIPIOS = [
  17, 8, 16, 16, 14, 14, 19, 8, 24, 21, 9, 30, 33, 21, 8, 17, 14, 5, 11, 11, 8, 17,
];

export function normalizarDpi(valor: string | null | undefined): string {
  return (valor ?? '').replace(/\D/g, '');
}

export interface ResultadoDpi {
  valido: boolean;
  motivo?: 'vacio' | 'longitud' | 'digito_verificador' | 'departamento' | 'municipio';
  mensaje?: string;
}

/** Réplica del algoritmo del CUI guatemalteco: 8 dígitos + verificador + depto + muni. */
export function validarDpi(valor: string | null | undefined): ResultadoDpi {
  const d = normalizarDpi(valor);
  if (!d) return { valido: false, motivo: 'vacio', mensaje: 'Ingrese su DPI.' };
  if (d.length !== 13) {
    return { valido: false, motivo: 'longitud', mensaje: 'El DPI debe tener 13 dígitos.' };
  }

  let suma = 0;
  for (let i = 0; i < 8; i++) suma += Number(d[i]) * (i + 2);
  if (suma % 11 !== Number(d[8])) {
    return {
      valido: false,
      motivo: 'digito_verificador',
      mensaje: 'El DPI no es válido; revise los dígitos.',
    };
  }

  const depto = Number(d.slice(9, 11));
  const muni = Number(d.slice(11, 13));
  if (depto < 1 || depto > 22) {
    return { valido: false, motivo: 'departamento', mensaje: 'El código de departamento no existe.' };
  }
  if (muni < 1 || muni > MUNICIPIOS[depto - 1] + 3) {
    return { valido: false, motivo: 'municipio', mensaje: 'El código de municipio no existe.' };
  }
  return { valido: true };
}

/** 2960123450101 → "2960 12345 0101" mientras el usuario escribe. */
export function formatearDpi(valor: string): string {
  const d = normalizarDpi(valor).slice(0, 13);
  const partes = [d.slice(0, 4), d.slice(4, 9), d.slice(9, 13)].filter(Boolean);
  return partes.join(' ');
}

export function formatearTelefono(valor: string | null | undefined): string {
  const d = (valor ?? '').replace(/\D/g, '');
  if (d.length === 8) return `${d.slice(0, 4)}-${d.slice(4)}`;
  if (d.length === 11 && d.startsWith('502')) {
    return `+502 ${d.slice(3, 7)}-${d.slice(7)}`;
  }
  return valor ?? '';
}

export function esEmailValido(valor: string | null | undefined): boolean {
  if (!valor) return false;
  return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(valor.trim());
}

// ---------------------------------------------------------------------------
// Fechas: todo se muestra en hora de Guatemala.
// ---------------------------------------------------------------------------

export function fechaLarga(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('es-GT', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: TZ,
  }).format(new Date(iso));
}

export function fechaCorta(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('es-GT', {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: TZ,
  }).format(new Date(iso));
}

export function horaCorta(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('es-GT', {
    hour: '2-digit', minute: '2-digit', hour12: true, timeZone: TZ,
  }).format(new Date(iso));
}

export function fechaHora(iso: string | null | undefined): string {
  if (!iso) return '—';
  return `${fechaCorta(iso)} · ${horaCorta(iso)}`;
}

export function haceCuanto(iso: string | null | undefined): string {
  if (!iso) return '—';
  const ms = Date.now() - new Date(iso).getTime();
  const min = Math.round(ms / 60000);
  if (min < 1) return 'hace un momento';
  if (min < 60) return `hace ${min} min`;
  const h = Math.round(min / 60);
  if (h < 24) return `hace ${h} h`;
  const d = Math.round(h / 24);
  if (d < 30) return `hace ${d} d`;
  return fechaCorta(iso);
}

/** "09:00" a partir de un ISO, en hora local de la clínica. */
export function horaDe(iso: string): string {
  const f = new Intl.DateTimeFormat('es-GT', {
    hour: '2-digit', minute: '2-digit', hour12: false, timeZone: TZ,
  }).format(new Date(iso));
  return f.replace(/^24:/, '00:');
}

/** Fecha yyyy-mm-dd de hoy en hora de Guatemala (no del navegador). */
export function hoyIso(): string {
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric', month: '2-digit', day: '2-digit', timeZone: TZ,
  }).format(new Date());
}

export function sumarDias(fechaIso: string, dias: number): string {
  const d = new Date(`${fechaIso}T12:00:00`);
  d.setDate(d.getDate() + dias);
  return d.toISOString().slice(0, 10);
}

export function moneda(valor: number | null | undefined, codigo = 'GTQ'): string {
  return new Intl.NumberFormat('es-GT', { style: 'currency', currency: codigo })
    .format(valor ?? 0);
}

/** Color según nivel de dolor 0-10, para el mapa corporal. */
export function colorDolor(nivel: number | null | undefined): string {
  const n = Math.max(0, Math.min(10, nivel ?? 0));
  if (n === 0) return '#cbd5e1';
  if (n <= 2) return '#4ade80';
  if (n <= 4) return '#facc15';
  if (n <= 6) return '#fb923c';
  if (n <= 8) return '#f43f5e';
  return '#b91c1c';
}

export function etiquetaDolor(nivel: number | null | undefined): string {
  const n = nivel ?? 0;
  if (n === 0) return 'Sin dolor';
  if (n <= 2) return 'Leve';
  if (n <= 4) return 'Moderado';
  if (n <= 6) return 'Considerable';
  if (n <= 8) return 'Intenso';
  return 'Insoportable';
}

export function iniciales(nombre: string | null | undefined): string {
  if (!nombre) return '??';
  return nombre
    .trim().split(/\s+/).slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('');
}
