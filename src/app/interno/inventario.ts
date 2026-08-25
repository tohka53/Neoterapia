import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { AuthService } from '../core/auth.service';
import { InventarioService } from '../core/api/inventario.service';
import {
  ArticuloInventario, CategoriaArticulo, ETIQUETAS_CATEGORIA, ETIQUETAS_MOVIMIENTO,
  MovimientoInventario, TipoMovimiento,
} from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaCorta, fechaHora } from '../core/util/formato';
import { Cargando, Dialogo, Vacio } from '../shared/ui';

/**
 * Existencias de la clínica.
 *
 * Todo el personal consulta; solo administración (admin y superadmin) crea
 * artículos y registra movimientos. La existencia nunca se edita a mano: la
 * calcula un trigger a partir de la bitácora, así el saldo siempre cuadra.
 */
@Component({
  selector: 'app-inventario',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Dialogo, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Inventario</h1>
          <p class="text-sm text-slate-500 mt-0.5">
            @if (puedeMover()) {
              La existencia no se edita: se mueve con entradas, salidas y ajustes,
              y cada movimiento queda en bitácora.
            } @else {
              Consulta de existencias. Los movimientos los registra administración.
            }
          </p>
        </div>
        @if (puedeMover()) {
          <button type="button" class="btn-primario" (click)="abrirArticulo(null)">
            Nuevo artículo
          </button>
        }
      </header>

      <div class="grid gap-3 sm:grid-cols-4 mb-5">
        @for (t of tarjetas(); track t.etiqueta) {
          <div class="tarjeta p-4">
            <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">{{ t.etiqueta }}</p>
            <p class="mt-1 text-2xl font-bold tabular-nums"
               [class.text-amber-600]="t.alerta && t.valor > 0">{{ t.valor }}</p>
          </div>
        }
      </div>

      <div class="tarjeta overflow-hidden">
        <header class="px-5 py-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
          <h2 class="font-semibold">Existencias</h2>
          <div class="flex flex-wrap gap-2">
            <input class="campo w-52 py-2" placeholder="Buscar artículo…"
                   [value]="busqueda()" (input)="buscar($event)">
            <select class="campo w-40 py-2" [value]="categoria()" (change)="filtrar($event)">
              <option value="">Todas</option>
              @for (c of categorias; track c) {
                <option [value]="c">{{ etiquetaCategoria(c) }}</option>
              }
            </select>
            <button type="button" class="btn-secundario btn-sm"
                    [class.ring-amber-400]="soloBajos()" (click)="alternarBajos()">
              {{ soloBajos() ? '✓ Bajo mínimo' : 'Bajo mínimo' }}
            </button>
          </div>
        </header>

        @if (cargando()) {
          <app-cargando />
        } @else if (articulos().length === 0) {
          <app-vacio titulo="Sin artículos en esta vista"
                     [detalle]="puedeMover()
                       ? 'Cree uno y cárguele existencia con un movimiento de entrada.'
                       : 'Todavía no hay artículos registrados.'" />
        } @else {
          <div class="overflow-x-auto">
            <table class="tabla">
              <thead><tr>
                <th>Código</th><th>Artículo</th><th>Categoría</th>
                <th class="text-right">Existencia</th><th class="text-right">Mínimo</th>
                <th>Ubicación</th><th>Últ. movimiento</th>
                @if (puedeMover()) { <th></th> }
              </tr></thead>
              <tbody>
                @for (a of articulos(); track a.id) {
                  <tr>
                    <td class="font-mono text-xs">{{ a.codigo }}</td>
                    <td>
                      <span class="font-medium text-sm">{{ a.nombre }}</span>
                      @if (a.descripcion) {
                        <p class="text-xs text-slate-500">{{ a.descripcion }}</p>
                      }
                    </td>
                    <td><span class="chip-neutro">{{ etiquetaCategoria(a.categoria) }}</span></td>
                    <td class="text-right">
                      <span class="font-semibold tabular-nums"
                            [class.text-rose-600]="a.agotado"
                            [class.text-amber-600]="a.bajo_minimo && !a.agotado">
                        {{ numero(a.existencia) }}
                      </span>
                      <span class="text-xs text-slate-400 ml-1">{{ a.unidad }}</span>
                      @if (a.agotado) {
                        <span class="block text-[10px] font-semibold text-rose-600 uppercase">Agotado</span>
                      } @else if (a.bajo_minimo) {
                        <span class="block text-[10px] font-semibold text-amber-600 uppercase">Bajo mínimo</span>
                      }
                    </td>
                    <td class="text-right tabular-nums text-slate-500">{{ numero(a.minimo) }}</td>
                    <td class="text-sm text-slate-500">{{ a.ubicacion ?? '—' }}</td>
                    <td class="text-xs text-slate-500 whitespace-nowrap">
                      @if (a.ultimo_movimiento) {
                        {{ fecha(a.ultimo_movimiento) }}
                        <span class="block text-slate-400">{{ etiquetaMovimiento(a.ultimo_tipo!) }}</span>
                      } @else { — }
                    </td>
                    @if (puedeMover()) {
                      <td class="text-right whitespace-nowrap">
                        <button type="button" class="btn-secundario btn-sm"
                                (click)="abrirMovimiento(a)">Mover</button>
                        <button type="button" class="btn-fantasma btn-sm"
                                (click)="abrirArticulo(a)">Editar</button>
                      </td>
                    }
                  </tr>
                }
              </tbody>
            </table>
          </div>
        }
      </div>

      <div class="tarjeta overflow-hidden mt-5">
        <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
          <h2 class="font-semibold">Movimientos recientes</h2>
          <span class="text-xs text-slate-400">La bitácora no se edita ni se borra</span>
        </header>
        @if (movimientos().length === 0) {
          <app-vacio titulo="Todavía no hay movimientos" />
        } @else {
          <div class="overflow-x-auto">
            <table class="tabla">
              <thead><tr>
                <th>Cuándo</th><th>Artículo</th><th>Tipo</th>
                <th class="text-right">Cantidad</th><th class="text-right">Quedó en</th>
                <th>Motivo</th><th>Responsable</th>
              </tr></thead>
              <tbody>
                @for (m of movimientos(); track m.id) {
                  <tr>
                    <td class="text-xs whitespace-nowrap">{{ fechaYHora(m.creado_en) }}</td>
                    <td class="text-sm">{{ m.articulo_nombre }}</td>
                    <td>
                      <span class="chip" [class]="claseMovimiento(m.tipo)">
                        {{ etiquetaMovimiento(m.tipo) }}
                      </span>
                    </td>
                    <td class="text-right tabular-nums font-medium">
                      {{ signo(m.tipo) }}{{ numero(m.cantidad) }}
                      <span class="text-xs text-slate-400 ml-0.5">{{ m.unidad }}</span>
                    </td>
                    <td class="text-right tabular-nums text-slate-500">
                      {{ numero(m.existencia_resultante) }}
                    </td>
                    <td class="text-sm text-slate-600 max-w-xs truncate" [title]="m.motivo ?? ''">
                      {{ m.motivo ?? '—' }}
                      @if (m.referencia) {
                        <span class="text-xs text-slate-400 block">{{ m.referencia }}</span>
                      }
                    </td>
                    <td class="text-sm">{{ m.responsable ?? '—' }}</td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        }
      </div>
    </div>

    <!-- ============ Artículo ============ -->
    <app-dialogo [(abierto)]="dlgArticulo"
                 [titulo]="artEdit()['id'] ? 'Editar artículo' : 'Nuevo artículo'" ancho="lg">
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="etiqueta" for="a-cod">Código</label>
          <input id="a-cod" class="campo font-mono uppercase" maxlength="20"
                 [value]="artEdit()['codigo'] ?? ''"
                 (input)="setArt('codigo', $any($event.target).value.toUpperCase())">
        </div>
        <div>
          <label class="etiqueta" for="a-nom">Nombre</label>
          <input id="a-nom" class="campo" [value]="artEdit()['nombre'] ?? ''"
                 (input)="setArt('nombre', $any($event.target).value)">
        </div>
        <div class="sm:col-span-2">
          <label class="etiqueta" for="a-desc">Descripción</label>
          <input id="a-desc" class="campo" [value]="artEdit()['descripcion'] ?? ''"
                 (input)="setArt('descripcion', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="a-cat">Categoría</label>
          <select id="a-cat" class="campo" [value]="artEdit()['categoria'] ?? 'insumo'"
                  (change)="setArt('categoria', $any($event.target).value)">
            @for (c of categorias; track c) {
              <option [value]="c">{{ etiquetaCategoria(c) }}</option>
            }
          </select>
        </div>
        <div>
          <label class="etiqueta" for="a-uni">Unidad de medida</label>
          <input id="a-uni" class="campo" placeholder="unidad, caja, rollo, par, ml…"
                 [value]="artEdit()['unidad'] ?? 'unidad'"
                 (input)="setArt('unidad', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="a-min">Existencia mínima</label>
          <input id="a-min" class="campo" type="number" min="0" step="0.01"
                 [value]="artEdit()['minimo'] ?? 0"
                 (input)="setArt('minimo', +$any($event.target).value)">
          <p class="ayuda">Por debajo de este valor el artículo se marca en ámbar.</p>
        </div>
        <div>
          <label class="etiqueta" for="a-ubi">Ubicación</label>
          <input id="a-ubi" class="campo" placeholder="Bodega, Consultorio 1…"
                 [value]="artEdit()['ubicacion'] ?? ''"
                 (input)="setArt('ubicacion', $any($event.target).value)">
        </div>
        <label class="sm:col-span-2 flex items-center gap-2 text-sm">
          <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                 [checked]="artEdit()['activo'] !== false"
                 (change)="setArt('activo', $any($event.target).checked)">
          Activo
        </label>

        @if (artEdit()['id']) {
          <p class="sm:col-span-2 rounded-lg bg-slate-50 ring-1 ring-slate-200 px-3 py-2 text-xs text-slate-600">
            La existencia actual ({{ numero(artEdit()['existencia'] ?? 0) }}) no se edita desde
            aquí. Use <strong>Mover</strong> y registre un ajuste por conteo físico.
          </p>
        }
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgArticulo.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!articuloValido() || guardando()"
                (click)="guardarArticulo()">Guardar</button>
      </div>
    </app-dialogo>

    <!-- ============ Movimiento ============ -->
    <app-dialogo [(abierto)]="dlgMovimiento" titulo="Registrar movimiento"
                 [subtitulo]="artMover()?.nombre ?? ''">
      @if (artMover(); as a) {
        <div class="space-y-4">
          <div class="rounded-lg bg-slate-50 ring-1 ring-slate-200 px-4 py-3 flex items-baseline justify-between">
            <span class="text-sm text-slate-600">Existencia actual</span>
            <span class="text-xl font-bold tabular-nums">
              {{ numero(a.existencia) }} <span class="text-sm font-normal text-slate-400">{{ a.unidad }}</span>
            </span>
          </div>

          <div>
            <span class="etiqueta">Tipo de movimiento</span>
            <div class="grid grid-cols-2 gap-2">
              @for (t of tiposMovimiento; track t) {
                <button type="button" class="rounded-lg px-3 py-2.5 text-sm ring-1 text-left transition-colors"
                        [class]="movTipo() === t
                          ? 'bg-marca-50 ring-marca-500 text-marca-900 font-medium'
                          : 'bg-white ring-slate-300 hover:bg-slate-50'"
                        (click)="movTipo.set(t)">
                  {{ etiquetaMovimiento(t) }}
                  <span class="block text-[11px] font-normal text-slate-500">{{ ayudaMovimiento(t) }}</span>
                </button>
              }
            </div>
          </div>

          <div>
            <label class="etiqueta" for="m-cant">
              {{ movTipo() === 'ajuste' ? 'Existencia real contada' : 'Cantidad' }}
            </label>
            <input id="m-cant" class="campo" type="number" min="0" step="0.01"
                   [value]="movCantidad()" (input)="movCantidad.set(+$any($event.target).value)">
            <p class="ayuda">
              @if (movTipo() === 'ajuste') {
                Queda en {{ numero(movCantidad()) }} {{ a.unidad }}, sin importar lo que hubiera.
              } @else {
                Quedaría en {{ numero(resultadoPrevisto()) }} {{ a.unidad }}.
              }
            </p>
          </div>

          <div>
            <label class="etiqueta" for="m-mot">Motivo</label>
            <input id="m-mot" class="campo" [value]="movMotivo()"
                   (input)="movMotivo.set($any($event.target).value)"
                   [placeholder]="marcadorMotivo()">
          </div>

          <div>
            <label class="etiqueta" for="m-ref">Referencia (opcional)</label>
            <input id="m-ref" class="campo" placeholder="Factura, orden de compra, lote…"
                   [value]="movReferencia()" (input)="movReferencia.set($any($event.target).value)">
          </div>

          @if (errorMovimiento()) {
            <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
              {{ errorMovimiento() }}
            </p>
          }
        </div>
      }
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgMovimiento.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!movimientoValido() || guardando()"
                (click)="guardarMovimiento()">
          {{ guardando() ? 'Registrando…' : 'Registrar' }}
        </button>
      </div>
    </app-dialogo>
  `,
})
export class Inventario {
  private readonly api = inject(InventarioService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly categorias: CategoriaArticulo[] =
    ['insumo', 'equipo', 'medicamento', 'limpieza', 'papeleria', 'otro'];
  readonly tiposMovimiento: TipoMovimiento[] = ['entrada', 'salida', 'merma', 'ajuste'];

  readonly cargando = signal(true);
  readonly guardando = signal(false);
  readonly articulos = signal<ArticuloInventario[]>([]);
  readonly movimientos = signal<MovimientoInventario[]>([]);
  readonly resumen = signal<Record<string, number>>({});
  readonly busqueda = signal('');
  readonly categoria = signal('');
  readonly soloBajos = signal(false);

  readonly dlgArticulo = signal(false);
  readonly artEdit = signal<Record<string, any>>({});
  readonly dlgMovimiento = signal(false);
  readonly artMover = signal<ArticuloInventario | null>(null);
  readonly movTipo = signal<TipoMovimiento>('entrada');
  readonly movCantidad = signal(0);
  readonly movMotivo = signal('');
  readonly movReferencia = signal('');
  readonly errorMovimiento = signal('');

  readonly fecha = fechaCorta;
  readonly fechaYHora = fechaHora;
  readonly puedeMover = computed(() => this.auth.esAdmin());

  private temporizador?: ReturnType<typeof setTimeout>;

  readonly numero = (n: number | null | undefined) =>
    new Intl.NumberFormat('es-GT', { maximumFractionDigits: 2 }).format(n ?? 0);

  etiquetaCategoria(c: CategoriaArticulo): string { return ETIQUETAS_CATEGORIA[c] ?? c; }
  etiquetaMovimiento(t: TipoMovimiento): string { return ETIQUETAS_MOVIMIENTO[t] ?? t; }

  ayudaMovimiento(t: TipoMovimiento): string {
    return {
      entrada: 'Compra, donación, devolución',
      salida: 'Consumo, uso en terapia',
      merma: 'Vencido, dañado, extraviado',
      ajuste: 'Fija la existencia al conteo',
    }[t];
  }

  claseMovimiento(t: TipoMovimiento): string {
    return {
      entrada: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
      salida: 'bg-slate-100 text-slate-700 ring-slate-300',
      merma: 'bg-rose-50 text-rose-800 ring-rose-200',
      ajuste: 'bg-indigo-50 text-indigo-800 ring-indigo-200',
    }[t];
  }

  signo(t: TipoMovimiento): string {
    return t === 'entrada' ? '+' : t === 'ajuste' ? '=' : '−';
  }

  readonly tarjetas = computed(() => {
    const r = this.resumen();
    return [
      { etiqueta: 'Artículos activos', valor: r['articulos'] ?? 0, alerta: false },
      { etiqueta: 'Bajo mínimo', valor: r['bajo_minimo'] ?? 0, alerta: true },
      { etiqueta: 'Agotados', valor: r['agotados'] ?? 0, alerta: true },
      { etiqueta: 'Movimientos (7 días)', valor: r['movimientos_semana'] ?? 0, alerta: false },
    ];
  });

  readonly articuloValido = computed(() => {
    const a = this.artEdit();
    return String(a['codigo'] ?? '').trim().length >= 2
      && String(a['nombre'] ?? '').trim().length >= 3
      && String(a['unidad'] ?? '').trim().length >= 1;
  });

  readonly resultadoPrevisto = computed(() => {
    const a = this.artMover();
    if (!a) return 0;
    const c = this.movCantidad();
    switch (this.movTipo()) {
      case 'entrada': return Number(a.existencia) + c;
      case 'ajuste': return c;
      default: return Number(a.existencia) - c;
    }
  });

  readonly movimientoValido = computed(() => {
    if (this.movCantidad() < 0) return false;
    if (this.movTipo() !== 'ajuste' && this.movCantidad() <= 0) return false;
    return this.resultadoPrevisto() >= 0;
  });

  readonly marcadorMotivo = computed(() => ({
    entrada: 'Compra a proveedor',
    salida: 'Consumo en terapia',
    merma: 'Producto vencido',
    ajuste: 'Conteo físico de fin de mes',
  } as Record<TipoMovimiento, string>)[this.movTipo()]);

  constructor() { void this.cargar(); }

  private async cargar() {
    this.cargando.set(true);
    try {
      const [arts, movs, res] = await Promise.all([
        this.api.articulos({
          texto: this.busqueda().trim() || undefined,
          categoria: this.categoria() || undefined,
          soloBajos: this.soloBajos(),
        }),
        this.api.movimientos({ limite: 40 }),
        this.api.resumen().catch(() => ({})),
      ]);
      this.articulos.set(arts);
      this.movimientos.set(movs);
      this.resumen.set(res as Record<string, number>);
    } catch (e) {
      this.avisos.error('No se pudo cargar el inventario.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  buscar(e: Event) {
    this.busqueda.set((e.target as HTMLInputElement).value);
    clearTimeout(this.temporizador);
    this.temporizador = setTimeout(() => void this.cargar(), 350);
  }

  filtrar(e: Event) {
    this.categoria.set((e.target as HTMLSelectElement).value);
    void this.cargar();
  }

  alternarBajos() {
    this.soloBajos.set(!this.soloBajos());
    void this.cargar();
  }

  abrirArticulo(a: ArticuloInventario | null) {
    this.artEdit.set(a ? { ...a } : {
      categoria: 'insumo', unidad: 'unidad', minimo: 0, activo: true,
    });
    this.dlgArticulo.set(true);
  }

  setArt(campo: string, valor: unknown) {
    this.artEdit.update((a) => ({ ...a, [campo]: valor }));
  }

  async guardarArticulo() {
    if (!this.articuloValido()) return;
    this.guardando.set(true);
    try {
      const a = { ...this.artEdit() };
      if (!a['id']) a['creado_por'] = this.auth.perfil()!.id;
      await this.api.guardarArticulo(a as Partial<ArticuloInventario>);
      this.avisos.exito('Artículo guardado.');
      this.dlgArticulo.set(false);
      await this.cargar();
    } catch (e) {
      this.avisos.error(
        e instanceof Error && /duplicate|23505/i.test(e.message)
          ? 'Ya existe un artículo con ese código.'
          : 'No se pudo guardar el artículo.',
      );
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  abrirMovimiento(a: ArticuloInventario) {
    this.artMover.set(a);
    this.movTipo.set('entrada');
    this.movCantidad.set(0);
    this.movMotivo.set('');
    this.movReferencia.set('');
    this.errorMovimiento.set('');
    this.dlgMovimiento.set(true);
  }

  async guardarMovimiento() {
    const a = this.artMover();
    if (!a || !this.movimientoValido()) return;
    this.guardando.set(true);
    this.errorMovimiento.set('');
    try {
      const r = await this.api.registrarMovimiento(
        a.id, this.movTipo(), this.movCantidad(),
        this.movMotivo() || null, this.movReferencia() || null,
      );
      if (!r.ok) {
        this.errorMovimiento.set(r.mensaje ?? 'No se pudo registrar el movimiento.');
        return;
      }
      this.avisos.exito(`${a.nombre}: quedó en ${this.numero(r.existencia)} ${a.unidad}.`);
      this.dlgMovimiento.set(false);
      await this.cargar();
    } catch (e) {
      this.errorMovimiento.set(
        e instanceof Error && /insufficient|permission/i.test(e.message)
          ? 'Su rol no permite mover el inventario.'
          : 'No se pudo registrar el movimiento.',
      );
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }
}
