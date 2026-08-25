import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../supabase.service';

export type Granularidad = 'day' | 'week' | 'month';

export interface ResumenKpis {
  desde: string;
  hasta: string;
  citas_totales: number;
  atendidas: number;
  canceladas: number;
  rechazadas: number;
  ausentes: number;
  confirmadas: number;
  solicitadas: number;
  pacientes_atendidos: number;
  pacientes_cancelados: number;
  pacientes_nuevos: number;
  atendidas_cobradas: number;
  atendidas_sin_cobrar: number;
  ingresos: number;
  pagos_registrados: number;
  pacientes_cobrados: number;
  ticket_promedio: number;
  ingresos_por_metodo: Record<string, number>;
  tasa_asistencia: number | null;
  tasa_cobro: number | null;
}

export interface PuntoSerie {
  periodo: string;
  ingresos: number;
  pagos: number;
  atendidas: number;
  canceladas: number;
  ausentes: number;
}

export interface VisitaSinCobrar {
  cita_id: string;
  codigo_referencia: string;
  fecha: string | null;
  paciente_id: string;
  paciente: string;
  dpi_mascara: string;
  fisioterapeuta: string | null;
  cargos: number;
}

@Injectable({ providedIn: 'root' })
export class IndicadoresService {
  private readonly sb = inject(SupabaseService);

  resumen(desde: string, hasta: string) {
    return this.sb.rpc<ResumenKpis>('kpis_resumen', { p_desde: desde, p_hasta: hasta });
  }

  async serie(desde: string, hasta: string, granularidad: Granularidad): Promise<PuntoSerie[]> {
    return (await this.sb.rpc<PuntoSerie[]>('kpis_serie', {
      p_desde: desde, p_hasta: hasta, p_granularidad: granularidad,
    })) ?? [];
  }

  async sinCobrar(desde: string, hasta: string): Promise<VisitaSinCobrar[]> {
    return (await this.sb.rpc<VisitaSinCobrar[]>('kpis_sin_cobrar', {
      p_desde: desde, p_hasta: hasta,
    })) ?? [];
  }
}
