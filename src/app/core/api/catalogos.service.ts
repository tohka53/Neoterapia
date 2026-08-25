import { Injectable, inject, signal } from '@angular/core';
import { SupabaseService } from '../supabase.service';
import { AreaCuerpo, Perfil, RolUsuario, Slot, Tratamiento } from '../modelos';

@Injectable({ providedIn: 'root' })
export class CatalogosService {
  private readonly sb = inject(SupabaseService);

  /** Catálogo del mapa corporal. Se cachea: cambia muy rara vez. */
  readonly areas = signal<AreaCuerpo[]>([]);
  private promesaAreas: Promise<AreaCuerpo[]> | null = null;

  async cargarAreas(): Promise<AreaCuerpo[]> {
    if (this.areas().length) return this.areas();
    this.promesaAreas ??= this.sb.rpc<AreaCuerpo[]>('areas_mapa').then((r) => {
      this.areas.set(r ?? []);
      return r ?? [];
    });
    return this.promesaAreas;
  }

  /**
   * Mapa codigo → id de las áreas. `areas_mapa()` (la RPC pública) no expone
   * los ids a propósito; el personal sí puede leerlos de la tabla.
   */
  private idsAreas: Map<string, string> | null = null;
  async idsDeAreas(): Promise<Map<string, string>> {
    if (this.idsAreas) return this.idsAreas;
    const { data, error } = await this.sb.desde('areas_cuerpo').select('id, codigo');
    if (error) throw error;
    this.idsAreas = new Map((data ?? []).map((a: any) => [a.codigo as string, a.id as string]));
    return this.idsAreas;
  }

  /** Disponibilidad pública. Nunca devuelve datos de pacientes. */
  async slots(fecha: string, fisioterapeutaId?: string | null): Promise<Slot[]> {
    return (await this.sb.rpc<Slot[]>('slots_disponibles', {
      p_fecha: fecha,
      p_fisioterapeuta_id: fisioterapeutaId ?? null,
    })) ?? [];
  }

  /**
   * Quién puede atender: no se filtra por rol sino por la marca `atiende`.
   * En una clínica pequeña el superadministrador también pasa consulta, y debe
   * poder aparecer en la agenda y quedar asignado a una cita.
   */
  async fisioterapeutas(): Promise<Perfil[]> {
    const { data, error } = await this.sb
      .desde('perfiles')
      .select('*')
      .eq('atiende', true)
      .eq('activo', true)
      .order('nombre_completo');
    if (error) throw error;
    return (data ?? []) as Perfil[];
  }

  /** Solo el superadministrador define quién atiende (lo vigila un trigger). */
  async marcarAtiende(usuarioId: string, atiende: boolean): Promise<void> {
    const { error } = await this.sb.desde('perfiles').update({ atiende }).eq('id', usuarioId);
    if (error) throw error;
  }

  async personal(): Promise<Perfil[]> {
    const { data, error } = await this.sb
      .desde('perfiles').select('*').order('rol').order('nombre_completo');
    if (error) throw error;
    return (data ?? []) as Perfil[];
  }

  /**
   * Alta de personal. Va por RPC y no por la Admin API de Supabase a propósito:
   * `auth.admin.createUser()` exigiría la service_role key en el navegador.
   * La función de Postgres valida que quien llama sea superadmin leyendo el JWT.
   */
  crearUsuario(datos: {
    email: string; clave: string; nombre: string; rol: RolUsuario;
    telefono?: string | null; colegiado?: string | null;
    especialidad?: string | null; color?: string | null; atiende?: boolean | null;
  }) {
    return this.sb.rpc<{ ok: boolean; usuario_id?: string; error?: string; mensaje?: string }>(
      'crear_usuario_personal', {
        p_email: datos.email,
        p_clave: datos.clave,
        p_nombre: datos.nombre,
        p_rol: datos.rol,
        p_telefono: datos.telefono ?? null,
        p_colegiado: datos.colegiado ?? null,
        p_especialidad: datos.especialidad ?? null,
        p_color: datos.color ?? null,
        p_atiende: datos.atiende ?? null,
      });
  }

  restablecerContrasena(usuarioId: string, clave: string) {
    return this.sb.rpc<{ ok: boolean; email?: string; error?: string; mensaje?: string }>(
      'restablecer_contrasena', { p_usuario_id: usuarioId, p_clave: clave });
  }

  async tratamientos(soloActivos = true): Promise<Tratamiento[]> {
    let q = this.sb.desde('tratamientos').select('*').order('nombre');
    if (soloActivos) q = q.eq('activo', true);
    const { data, error } = await q;
    if (error) throw error;
    return (data ?? []) as Tratamiento[];
  }

  async guardarTratamiento(t: Partial<Tratamiento>): Promise<void> {
    const { error } = t.id
      ? await this.sb.desde('tratamientos').update(t).eq('id', t.id)
      : await this.sb.desde('tratamientos').insert(t);
    if (error) throw error;
  }

  async configuracion(): Promise<Record<string, unknown>> {
    const { data, error } = await this.sb.desde('configuracion').select('clave, valor, descripcion');
    if (error) throw error;
    const mapa: Record<string, unknown> = {};
    for (const fila of data ?? []) mapa[(fila as any).clave] = (fila as any).valor;
    return mapa;
  }

  async guardarConfiguracion(clave: string, valor: unknown): Promise<void> {
    const { error } = await this.sb.desde('configuracion').update({ valor }).eq('clave', clave);
    if (error) throw error;
  }

  async horarios() {
    const { data, error } = await this.sb
      .desde('horarios_atencion').select('*, perfiles(nombre_completo)')
      .order('dia_semana').order('hora_inicio');
    if (error) throw error;
    return data ?? [];
  }

  async guardarHorario(h: Record<string, unknown>) {
    const { error } = h['id']
      ? await this.sb.desde('horarios_atencion').update(h).eq('id', h['id'] as string)
      : await this.sb.desde('horarios_atencion').insert(h);
    if (error) throw error;
  }

  async eliminarHorario(id: string) {
    const { error } = await this.sb.desde('horarios_atencion').delete().eq('id', id);
    if (error) throw error;
  }
}
