import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../supabase.service';
import {
  Alerta, Duplicado, MomentoMapa, PacienteListado, PuntoEvolucion,
} from '../modelos';

@Injectable({ providedIn: 'root' })
export class PacientesService {
  private readonly sb = inject(SupabaseService);

  async listar(opciones: {
    texto?: string; estado?: string; fisioterapeutaId?: string | null; limite?: number;
  } = {}): Promise<PacienteListado[]> {
    if (opciones.texto?.trim()) {
      const filas = await this.sb.rpc<any[]>('buscar_pacientes', {
        p_texto: opciones.texto.trim(),
        p_limite: opciones.limite ?? 50,
      });
      const ids = (filas ?? []).map((f) => f.id);
      if (!ids.length) return [];
      const { data, error } = await this.sb
        .desde('v_pacientes_listado').select('*').in('id', ids);
      if (error) throw error;
      // Se respeta el orden de relevancia que devolvió la búsqueda.
      const mapa = new Map((data ?? []).map((p: any) => [p.id, p]));
      return ids.map((id) => mapa.get(id)).filter(Boolean) as PacienteListado[];
    }

    let q = this.sb.desde('v_pacientes_listado').select('*');
    if (opciones.estado) q = q.eq('estado', opciones.estado);
    else q = q.neq('estado', 'fusionado');
    if (opciones.fisioterapeutaId) q = q.eq('fisioterapeuta_id', opciones.fisioterapeutaId);
    const { data, error } = await q
      .order('creado_en', { ascending: false })
      .limit(opciones.limite ?? 100);
    if (error) throw error;
    return (data ?? []) as PacienteListado[];
  }

  async obtener(id: string): Promise<PacienteListado | null> {
    const { data, error } = await this.sb
      .desde('v_pacientes_listado').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return (data ?? null) as PacienteListado | null;
  }

  async actualizar(id: string, cambios: Record<string, unknown>): Promise<void> {
    const { error } = await this.sb.desde('pacientes').update(cambios).eq('id', id);
    if (error) throw error;
  }

  registrar(datos: Record<string, unknown>) {
    return this.sb.rpc<{ ok: boolean; paciente_id?: string; error?: string }>(
      'registrar_paciente', { p_datos: datos });
  }

  /** Destapa el DPI completo. Queda registrado en auditoría. */
  verDpi(pacienteId: string, motivo?: string) {
    return this.sb.rpc<{ documento: string; tipo: string }>('ver_dpi_paciente', {
      p_paciente_id: pacienteId,
      p_motivo: motivo ?? null,
    });
  }

  corregirDpi(pacienteId: string, nuevoDpi: string, motivo: string, tipo = 'dpi') {
    return this.sb.rpc<{ ok: boolean; error?: string; mensaje?: string; paciente_id?: string; dpi_mascara?: string }>(
      'corregir_dpi', {
        p_paciente_id: pacienteId, p_nuevo_dpi: nuevoDpi, p_motivo: motivo, p_tipo: tipo,
      });
  }

  fusionar(origenId: string, destinoId: string, motivo: string) {
    return this.sb.rpc<{ ok: boolean; error?: string; movido?: Record<string, number> }>(
      'fusionar_pacientes', {
        p_origen_id: origenId, p_destino_id: destinoId, p_motivo: motivo,
      });
  }

  // --- Clínico ------------------------------------------------------------

  async datosClinicos(pacienteId: string) {
    const { data, error } = await this.sb
      .desde('pacientes_clinico').select('*').eq('paciente_id', pacienteId).maybeSingle();
    if (error) throw error;
    return data;
  }

  async guardarDatosClinicos(pacienteId: string, datos: Record<string, unknown>) {
    const { error } = await this.sb
      .desde('pacientes_clinico')
      .upsert({ paciente_id: pacienteId, ...datos }, { onConflict: 'paciente_id' });
    if (error) throw error;
  }

  /** Un mapa por momento (solicitud y cada sesión), para recorrer el historial. */
  async historialMapa(pacienteId: string): Promise<MomentoMapa[]> {
    return (await this.sb.rpc<MomentoMapa[]>('historial_mapa_corporal', {
      p_paciente_id: pacienteId,
    })) ?? [];
  }

  async evolucion(pacienteId: string): Promise<PuntoEvolucion[]> {
    return (await this.sb.rpc<PuntoEvolucion[]>('mapa_evolucion', {
      p_paciente_id: pacienteId,
    })) ?? [];
  }

  async saldo(pacienteId: string) {
    const { data, error } = await this.sb
      .desde('v_saldos_paciente').select('*').eq('paciente_id', pacienteId).maybeSingle();
    if (error) throw error;
    return data as { total_cargos: number; total_pagado: number; saldo: number } | null;
  }

  async historialIdentidad(pacienteId: string) {
    const { data, error } = await this.sb
      .desde('pacientes_historial_identidad')
      .select('*, perfiles:realizado_por(nombre_completo)')
      .eq('paciente_id', pacienteId)
      .order('realizado_en', { ascending: false });
    if (error) throw error;
    return data ?? [];
  }

  // --- Alertas y duplicados ----------------------------------------------

  async alertas(estado: 'pendiente' | 'revisada' | 'descartada' | 'todas' = 'pendiente'): Promise<Alerta[]> {
    let q = this.sb.desde('alertas').select('*');
    if (estado !== 'todas') q = q.eq('estado', estado);
    const { data, error } = await q.order('severidad', { ascending: false })
      .order('creado_en', { ascending: false }).limit(200);
    if (error) throw error;
    return (data ?? []) as Alerta[];
  }

  async alertasDePaciente(pacienteId: string): Promise<Alerta[]> {
    const { data, error } = await this.sb
      .desde('alertas').select('*').eq('paciente_id', pacienteId)
      .order('creado_en', { ascending: false });
    if (error) throw error;
    return (data ?? []) as Alerta[];
  }

  async resolverAlerta(id: string, estado: 'revisada' | 'descartada', nota?: string) {
    const { error } = await this.sb.desde('alertas').update({
      estado, nota_revision: nota ?? null, revisada_en: new Date().toISOString(),
    }).eq('id', id);
    if (error) throw error;
  }

  async duplicados(estado = 'pendiente'): Promise<Duplicado[]> {
    const { data, error } = await this.sb
      .desde('v_duplicados').select('*').eq('estado', estado)
      .order('puntaje', { ascending: false }).limit(100);
    if (error) throw error;
    return (data ?? []) as Duplicado[];
  }

  async descartarDuplicado(id: string, nota?: string) {
    const { error } = await this.sb.desde('posibles_duplicados').update({
      estado: 'descartado', nota: nota ?? null, revisado_en: new Date().toISOString(),
    }).eq('id', id);
    if (error) throw error;
  }

  detectarDuplicados(pacienteId: string) {
    return this.sb.rpc<number>('detectar_duplicados', { p_paciente_id: pacienteId });
  }
}
