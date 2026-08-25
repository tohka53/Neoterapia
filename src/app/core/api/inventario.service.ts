import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../supabase.service';
import { ArticuloInventario, MovimientoInventario, TipoMovimiento } from '../modelos';

/**
 * Existencias de la clínica.
 *
 * Todo el personal consulta; solo administración (admin y superadmin) crea
 * artículos y registra movimientos. La existencia **nunca** se escribe
 * directamente: la calcula un trigger a partir de la bitácora, de modo que el
 * saldo siempre cuadra con los movimientos.
 */
@Injectable({ providedIn: 'root' })
export class InventarioService {
  private readonly sb = inject(SupabaseService);

  async articulos(opciones: {
    texto?: string; categoria?: string; soloBajos?: boolean; incluirInactivos?: boolean;
  } = {}): Promise<ArticuloInventario[]> {
    let q = this.sb.desde('v_inventario').select('*');
    if (!opciones.incluirInactivos) q = q.eq('activo', true);
    if (opciones.categoria) q = q.eq('categoria', opciones.categoria);
    if (opciones.soloBajos) q = q.eq('bajo_minimo', true);
    if (opciones.texto?.trim()) {
      const t = opciones.texto.trim();
      q = q.or(`nombre.ilike.%${t}%,codigo.ilike.%${t}%,descripcion.ilike.%${t}%`);
    }
    const { data, error } = await q.order('nombre').limit(300);
    if (error) throw error;
    return (data ?? []) as ArticuloInventario[];
  }

  async guardarArticulo(a: Partial<ArticuloInventario>): Promise<void> {
    // `existencia` se omite siempre: la protege un trigger.
    const { id, existencia, bajo_minimo, agotado, ultimo_movimiento, ultimo_tipo,
            creado_por_nombre, creado_en, ...campos } = a as Record<string, unknown> & { id?: string };
    void existencia; void bajo_minimo; void agotado; void ultimo_movimiento;
    void ultimo_tipo; void creado_por_nombre; void creado_en;

    const { error } = id
      ? await this.sb.desde('inventario_articulos').update(campos).eq('id', id)
      : await this.sb.desde('inventario_articulos').insert(campos);
    if (error) throw error;
  }

  registrarMovimiento(
    articuloId: string, tipo: TipoMovimiento, cantidad: number,
    motivo?: string | null, referencia?: string | null,
  ) {
    return this.sb.rpc<{ ok: boolean; existencia?: number; error?: string; mensaje?: string }>(
      'registrar_movimiento_inventario', {
        p_articulo_id: articuloId,
        p_tipo: tipo,
        p_cantidad: cantidad,
        p_motivo: motivo ?? null,
        p_referencia: referencia ?? null,
      });
  }

  async movimientos(opciones: { articuloId?: string; limite?: number } = {}): Promise<MovimientoInventario[]> {
    let q = this.sb.desde('v_inventario_movimientos').select('*');
    if (opciones.articuloId) q = q.eq('articulo_id', opciones.articuloId);
    const { data, error } = await q
      .order('creado_en', { ascending: false })
      .limit(opciones.limite ?? 100);
    if (error) throw error;
    return (data ?? []) as MovimientoInventario[];
  }

  resumen() {
    return this.sb.rpc<Record<string, number>>('resumen_inventario');
  }
}
