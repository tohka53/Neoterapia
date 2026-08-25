import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../supabase.service';
import { AreaMarcada, Pago, SesionDetalle } from '../modelos';

@Injectable({ providedIn: 'root' })
export class ClinicaService {
  private readonly sb = inject(SupabaseService);

  // --- Sesiones -----------------------------------------------------------

  async sesionesDePaciente(pacienteId: string): Promise<SesionDetalle[]> {
    const { data, error } = await this.sb
      .desde('v_sesiones_detalle').select('*')
      .eq('paciente_id', pacienteId)
      .order('inicio', { ascending: false });
    if (error) throw error;
    return (data ?? []) as SesionDetalle[];
  }

  async sesion(id: string): Promise<SesionDetalle | null> {
    const { data, error } = await this.sb
      .desde('v_sesiones_detalle').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return (data ?? null) as SesionDetalle | null;
  }

  async sesionDeCita(citaId: string): Promise<SesionDetalle | null> {
    const { data, error } = await this.sb
      .desde('v_sesiones_detalle').select('*').eq('cita_id', citaId).maybeSingle();
    if (error) throw error;
    return (data ?? null) as SesionDetalle | null;
  }

  async guardarSesion(id: string, cambios: Record<string, unknown>): Promise<void> {
    const { error } = await this.sb.desde('sesiones').update(cambios).eq('id', id);
    if (error) throw error;
  }

  firmar(sesionId: string) {
    return this.sb.rpc<{ ok: boolean; error?: string }>('firmar_sesion', { p_sesion_id: sesionId });
  }

  async agregarAdenda(sesionId: string, texto: string, autorId: string) {
    const { error } = await this.sb.desde('sesiones_adendas')
      .insert({ sesion_id: sesionId, texto, autor_id: autorId });
    if (error) throw error;
  }

  async adendas(sesionId: string) {
    const { data, error } = await this.sb
      .desde('sesiones_adendas').select('*, perfiles:autor_id(nombre_completo)')
      .eq('sesion_id', sesionId).order('creado_en');
    if (error) throw error;
    return data ?? [];
  }

  // --- Mapa corporal de la sesión ----------------------------------------

  /** Reemplaza el mapa de la sesión por el estado que dejó el fisioterapeuta. */
  async guardarAreasSesion(sesionId: string, areas: AreaMarcada[], idsPorCodigo: Map<string, string>) {
    const { error: errBorrar } = await this.sb
      .desde('sesion_areas').delete().eq('sesion_id', sesionId);
    if (errBorrar) throw errBorrar;

    if (!areas.length) return;
    const filas = areas.map((a) => ({
      sesion_id: sesionId,
      area_id: idsPorCodigo.get(a.codigo),
      nivel_dolor: a.nivel_dolor ?? 0,
      movilidad: a.movilidad ?? null,
      inflamacion: a.inflamacion ?? false,
      observacion: a.observacion ?? null,
    })).filter((f) => f.area_id);

    const { error } = await this.sb.desde('sesion_areas').insert(filas);
    if (error) throw error;
  }

  // --- Tratamientos aplicados --------------------------------------------

  /** El precio ya no viene del catálogo: se escribe al aplicar el tratamiento. */
  async agregarTratamiento(
    sesionId: string, tratamientoId: string, cantidad = 1,
    precio = 0, notas?: string,
  ) {
    const { error } = await this.sb.desde('sesion_tratamientos').insert({
      sesion_id: sesionId, tratamiento_id: tratamientoId, cantidad,
      precio_aplicado: precio, notas: notas ?? null,
    });
    if (error) throw error;
  }

  async quitarTratamiento(id: string) {
    const { error } = await this.sb.desde('sesion_tratamientos').delete().eq('id', id);
    if (error) throw error;
  }

  // --- Pagos --------------------------------------------------------------

  async pagos(filtro: { pacienteId?: string; desde?: string; hasta?: string; limite?: number } = {}): Promise<Pago[]> {
    let q = this.sb.desde('pagos').select('*');
    if (filtro.pacienteId) q = q.eq('paciente_id', filtro.pacienteId);
    if (filtro.desde) q = q.gte('fecha', `${filtro.desde}T00:00:00-06:00`);
    if (filtro.hasta) q = q.lte('fecha', `${filtro.hasta}T23:59:59-06:00`);
    const { data, error } = await q.order('fecha', { ascending: false }).limit(filtro.limite ?? 200);
    if (error) throw error;
    return (data ?? []) as Pago[];
  }

  async registrarPago(pago: Partial<Pago>): Promise<void> {
    const { error } = await this.sb.desde('pagos').insert(pago);
    if (error) throw error;
  }

  async anularPago(id: string, motivo: string): Promise<void> {
    const { error } = await this.sb.desde('pagos').update({
      estado: 'anulado', anulado_en: new Date().toISOString(), motivo_anulacion: motivo,
    }).eq('id', id);
    if (error) throw error;
  }

  async evaluacionDeCita(citaId: string) {
    const { data, error } = await this.sb
      .desde('evaluaciones').select('*').eq('cita_id', citaId).maybeSingle();
    if (error) throw error;
    return data;
  }
}
