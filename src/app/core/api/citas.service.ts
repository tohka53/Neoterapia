import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../supabase.service';
import {
  CitaListado, EstadoCita, EventoAgenda, RespuestaSolicitud, SolicitudCita,
} from '../modelos';

export interface FiltroCitas {
  estados?: EstadoCita[];
  desde?: string;
  hasta?: string;
  fisioterapeutaId?: string | null;
  pacienteId?: string;
  texto?: string;
  limite?: number;
}

@Injectable({ providedIn: 'root' })
export class CitasService {
  private readonly sb = inject(SupabaseService);

  // --- Público ------------------------------------------------------------

  /** Única vía por la que un paciente pide cita. No crea cuenta ni sesión. */
  async solicitar(datos: SolicitudCita): Promise<RespuestaSolicitud> {
    return this.sb.rpc<RespuestaSolicitud>('solicitar_cita', { p_datos: datos });
  }

  async contextoEnlace(token: string) {
    return this.sb.rpc<Record<string, unknown>>('cita_publica_por_token', { p_token: token });
  }

  async usarEnlace(token: string, datos: Record<string, unknown> = {}) {
    return this.sb.rpc<Record<string, unknown>>('usar_enlace_accion', {
      p_token: token, p_datos: datos,
    });
  }

  // --- Interno ------------------------------------------------------------

  async listar(filtro: FiltroCitas = {}): Promise<CitaListado[]> {
    let q = this.sb.desde('v_solicitudes').select('*');

    if (filtro.estados?.length) q = q.in('estado', filtro.estados);
    if (filtro.pacienteId) q = q.eq('paciente_id', filtro.pacienteId);
    if (filtro.fisioterapeutaId) q = q.eq('fisioterapeuta_id', filtro.fisioterapeutaId);
    if (filtro.desde) q = q.gte('fecha_solicitada', filtro.desde);
    if (filtro.hasta) q = q.lte('fecha_solicitada', filtro.hasta);
    if (filtro.texto) {
      const t = filtro.texto.trim();
      q = q.or(`codigo_referencia.ilike.%${t}%,nombre_completo.ilike.%${t}%,nombre_declarado.ilike.%${t}%`);
    }

    const { data, error } = await q
      .order('fecha_solicitada', { ascending: true })
      .order('creado_en', { ascending: true })
      .limit(filtro.limite ?? 200);
    if (error) throw error;
    return (data ?? []) as CitaListado[];
  }

  async obtener(id: string): Promise<CitaListado | null> {
    const { data, error } = await this.sb
      .desde('v_solicitudes').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return (data ?? null) as CitaListado | null;
  }

  async agenda(desde: string, hasta: string, fisioterapeutaId?: string | null): Promise<EventoAgenda[]> {
    let q = this.sb.desde('v_agenda').select('*')
      .gte('inicio', `${desde}T00:00:00-06:00`)
      .lte('inicio', `${hasta}T23:59:59-06:00`);
    if (fisioterapeutaId) q = q.eq('fisioterapeuta_id', fisioterapeutaId);
    const { data, error } = await q.order('inicio');
    if (error) throw error;
    return (data ?? []) as EventoAgenda[];
  }

  confirmar(citaId: string, inicioIso: string, fisioterapeutaId: string, opciones: {
    duracionMin?: number; consultorio?: string | null; nota?: string | null;
  } = {}) {
    return this.sb.rpc<{ ok: boolean; error?: string; mensaje?: string; enlaces?: Record<string, string> }>(
      'confirmar_cita', {
        p_cita_id: citaId,
        p_inicio: inicioIso,
        p_fisioterapeuta_id: fisioterapeutaId,
        p_duracion_min: opciones.duracionMin ?? null,
        p_consultorio: opciones.consultorio ?? null,
        p_nota: opciones.nota ?? null,
      });
  }

  rechazar(citaId: string, motivo: string) {
    return this.sb.rpc<{ ok: boolean; error?: string }>('rechazar_cita', {
      p_cita_id: citaId, p_motivo: motivo,
    });
  }

  cancelar(citaId: string, motivo: string) {
    return this.sb.rpc<{ ok: boolean; error?: string }>('cancelar_cita', {
      p_cita_id: citaId, p_motivo: motivo,
    });
  }

  reprogramar(citaId: string, nuevoInicioIso: string, fisioterapeutaId: string | null, motivo: string) {
    return this.sb.rpc<{ ok: boolean; error?: string; mensaje?: string; codigo_referencia?: string; enlaces?: Record<string, string> }>(
      'reprogramar_cita', {
        p_cita_id: citaId,
        p_nuevo_inicio: nuevoInicioIso,
        p_fisioterapeuta_id: fisioterapeutaId,
        p_motivo: motivo,
        p_duracion_min: null,
      });
  }

  marcarAsistencia(citaId: string, asistio: boolean) {
    return this.sb.rpc<{ ok: boolean; estado: EstadoCita; sesion_id?: string }>(
      'marcar_asistencia', { p_cita_id: citaId, p_asistio: asistio });
  }

  enlaces(citaId: string) {
    return this.sb.rpc<Record<string, string>>('emitir_enlaces_cita', { p_cita_id: citaId });
  }

  async historialEstado(citaId: string) {
    const { data, error } = await this.sb
      .desde('citas_historial_estado')
      .select('*, perfiles:realizado_por(nombre_completo)')
      .eq('cita_id', citaId)
      .order('realizado_en', { ascending: false });
    if (error) throw error;
    return data ?? [];
  }

  async mensajes(citaId: string) {
    const { data, error } = await this.sb
      .desde('mensajes').select('*').eq('cita_id', citaId)
      .order('creado_en', { ascending: false });
    if (error) throw error;
    return data ?? [];
  }

  async metricas() {
    return this.sb.rpc<Record<string, number>>('metricas_tablero');
  }
}
