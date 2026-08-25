import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  Granularidad, IndicadoresService, PuntoSerie, ResumenKpis, VisitaSinCobrar,
} from '../core/api/indicadores.service';
import { AvisosService } from '../core/util/avisos.service';
import { fechaCorta, hoyIso, moneda, sumarDias } from '../core/util/formato';
import { Cargando, Vacio } from '../shared/ui';

/**
 * Indicadores de operación y cobro.
 *
 * Decisiones de la gráfica, según la guía de visualización:
 *  - Los titulares son **tiles**, no una gráfica de una barra.
 *  - Los ingresos en el tiempo son **una sola serie** → un solo tono, sin leyenda:
 *    el título ya dice qué se está viendo.
 *  - Nada de doble eje: las citas del período viajan en el tooltip, no en un
 *    segundo eje que obligaría a comparar escalas distintas.
 *  - Los colores de estado (ámbar = sin cobrar, rosa = canceladas) van siempre
 *    con etiqueta, nunca solo el color.
 */
@Component({
  selector: 'app-indicadores',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="mb-5">
        <h1 class="text-2xl font-bold tracking-tight">Indicadores</h1>
        <p class="text-sm text-slate-500 mt-0.5">
          Atención y cobro del período. Todo se cuenta en hora de Guatemala.
        </p>
      </header>

      <!-- Filtros: una sola fila, arriba de todo -->
      <div class="flex flex-wrap items-end gap-2 mb-5">
        <div class="flex flex-wrap gap-1.5">
          @for (r of rangos; track r.id) {
            <button type="button" class="btn-secundario btn-sm"
                    [class.ring-marca-500]="rangoActivo() === r.id"
                    [class.text-marca-800]="rangoActivo() === r.id"
                    (click)="aplicarRango(r.id)">{{ r.etiqueta }}</button>
          }
        </div>
        <div class="flex items-center gap-1.5">
          <input id="kpi-desde" class="campo w-40 py-2" type="date" aria-label="Desde"
                 [value]="desde()" (change)="cambiarFecha('desde', $event)">
          <span class="text-slate-400 text-sm">a</span>
          <input id="kpi-hasta" class="campo w-40 py-2" type="date" aria-label="Hasta"
                 [value]="hasta()" (change)="cambiarFecha('hasta', $event)">
        </div>
        <div class="flex rounded-lg ring-1 ring-slate-300 overflow-hidden ml-auto">
          @for (g of granularidades; track g.id) {
            <button type="button" class="px-3 py-2 text-sm transition-colors"
                    [class]="granularidad() === g.id
                      ? 'bg-marca-600 text-white' : 'bg-white hover:bg-slate-50'"
                    (click)="cambiarGranularidad(g.id)">{{ g.etiqueta }}</button>
          }
        </div>
      </div>

      @if (cargando()) {
        <app-cargando texto="Calculando indicadores…" />
      } @else if (resumen(); as k) {

        <!-- ============ Titulares ============ -->
        <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-3">
          <div class="tarjeta p-5">
            <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">
              Dinero ingresado
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums" style="color: var(--kpi-acento)">
              {{ dinero(k.ingresos) }}
            </p>
            <p class="mt-1 text-xs text-slate-500">
              {{ k.pagos_registrados }} pago{{ k.pagos_registrados === 1 ? '' : 's' }} ·
              promedio {{ dinero(k.ticket_promedio) }}
            </p>
          </div>

          @for (t of tiles(); track t.etiqueta) {
            <div class="tarjeta p-5">
              <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">
                {{ t.etiqueta }}
              </p>
              <p class="mt-1 text-3xl font-bold tabular-nums" [style.color]="t.color">
                {{ t.valor }}
              </p>
              <p class="mt-1 text-xs text-slate-500">{{ t.pie }}</p>
            </div>
          }
        </section>

        <!-- ============ Ingresos en el tiempo ============ -->
        <section class="tarjeta tarjeta-cuerpo mb-5">
          <div class="flex flex-wrap items-baseline justify-between gap-3 mb-1">
            <h2 class="font-semibold">Dinero ingresado por {{ etiquetaGranularidad() }}</h2>
            <span class="text-sm text-slate-500">
              Máximo {{ dinero(maximoSerie()) }} · total {{ dinero(k.ingresos) }}
            </span>
          </div>
          <p class="text-sm text-slate-500 mb-5">
            Pase el cursor sobre una barra para ver el detalle de ese período.
          </p>

          @if (serie().length === 0) {
            <app-vacio titulo="No hay períodos en este rango" />
          } @else {
            <div class="relative">
              <!-- Líneas guía, deliberadamente tenues -->
              <div class="absolute inset-x-0 top-0 h-48 pointer-events-none">
                @for (g of guias(); track g.valor) {
                  <div class="absolute inset-x-0 border-t border-slate-100 flex justify-end"
                       [style.top.%]="g.posicion">
                    <span class="text-[10px] text-slate-400 -mt-2 bg-white pl-1">
                      {{ dineroCorto(g.valor) }}
                    </span>
                  </div>
                }
              </div>

              <div class="relative flex items-end gap-[2px] h-48"
                   [style.--kpi-acento]="acento">
                @for (p of serie(); track p.periodo) {
                  <div class="group relative flex-1 h-full flex flex-col justify-end min-w-1">
                    <!-- Área de contacto más grande que la barra -->
                    <div class="absolute inset-0 -top-2 cursor-default"></div>

                    <div class="w-full rounded-t transition-[height] duration-200"
                         [style.height.%]="altura(p.ingresos)"
                         [style.background]="p.ingresos > 0 ? acento : '#e2e8f0'"
                         [style.min-height.px]="p.ingresos > 0 ? 3 : 2"></div>

                    <!-- Tooltip -->
                    <div class="pointer-events-none absolute bottom-full left-1/2 -translate-x-1/2 mb-2
                                hidden group-hover:block z-20 w-44">
                      <div class="rounded-lg bg-slate-900 text-white px-3 py-2 shadow-lg">
                        <p class="text-xs font-semibold">{{ etiquetaPeriodo(p.periodo) }}</p>
                        <p class="mt-1 text-sm font-bold tabular-nums">{{ dinero(p.ingresos) }}</p>
                        <dl class="mt-1.5 space-y-0.5 text-[11px] text-slate-300">
                          <div class="flex justify-between gap-3">
                            <dt>Pagos</dt><dd class="tabular-nums">{{ p.pagos }}</dd>
                          </div>
                          <div class="flex justify-between gap-3">
                            <dt>Atendidas</dt><dd class="tabular-nums">{{ p.atendidas }}</dd>
                          </div>
                          <div class="flex justify-between gap-3">
                            <dt>Canceladas</dt><dd class="tabular-nums">{{ p.canceladas }}</dd>
                          </div>
                          <div class="flex justify-between gap-3">
                            <dt>No asistió</dt><dd class="tabular-nums">{{ p.ausentes }}</dd>
                          </div>
                        </dl>
                      </div>
                    </div>
                  </div>
                }
              </div>

              <!-- Eje: solo algunas etiquetas, para que no choquen -->
              <div class="flex gap-[2px] mt-1.5">
                @for (p of serie(); track p.periodo; let i = $index) {
                  <div class="flex-1 min-w-1 text-center">
                    @if (mostrarEtiqueta(i)) {
                      <span class="text-[10px] text-slate-400 whitespace-nowrap">
                        {{ etiquetaEje(p.periodo) }}
                      </span>
                    }
                  </div>
                }
              </div>
            </div>
          }

          <!-- Vista de tabla, para lectura exacta y accesible -->
          <details class="mt-5">
            <summary class="cursor-pointer text-sm text-slate-500 hover:text-slate-700">
              Ver los datos en tabla
            </summary>
            <div class="mt-3 overflow-x-auto max-h-72">
              <table class="tabla">
                <thead><tr>
                  <th>Período</th><th class="text-right">Ingresos</th>
                  <th class="text-right">Pagos</th><th class="text-right">Atendidas</th>
                  <th class="text-right">Canceladas</th><th class="text-right">No asistió</th>
                </tr></thead>
                <tbody>
                  @for (p of serie(); track p.periodo) {
                    <tr>
                      <td class="whitespace-nowrap">{{ etiquetaPeriodo(p.periodo) }}</td>
                      <td class="text-right tabular-nums font-medium">{{ dinero(p.ingresos) }}</td>
                      <td class="text-right tabular-nums">{{ p.pagos }}</td>
                      <td class="text-right tabular-nums">{{ p.atendidas }}</td>
                      <td class="text-right tabular-nums">{{ p.canceladas }}</td>
                      <td class="text-right tabular-nums">{{ p.ausentes }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </details>
        </section>

        <div class="grid gap-5 lg:grid-cols-5">
          <!-- ============ Por método de pago ============ -->
          <section class="tarjeta tarjeta-cuerpo lg:col-span-2">
            <h2 class="font-semibold mb-1">Por método de pago</h2>
            <p class="text-sm text-slate-500 mb-4">Del dinero ingresado en el período.</p>

            @if (porMetodo().length === 0) {
              <app-vacio titulo="Sin pagos en el período" />
            } @else {
              <ul class="space-y-3">
                @for (m of porMetodo(); track m.metodo) {
                  <li>
                    <div class="flex items-baseline justify-between text-sm mb-1">
                      <span class="capitalize">{{ m.metodo }}</span>
                      <span class="tabular-nums">
                        <strong>{{ dinero(m.monto) }}</strong>
                        <span class="text-slate-400 ml-1.5">{{ m.porcentaje }}%</span>
                      </span>
                    </div>
                    <div class="h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div class="h-full rounded-full" [style.width.%]="m.porcentaje"
                           [style.background]="acento"></div>
                    </div>
                  </li>
                }
              </ul>
            }
          </section>

          <!-- ============ Visitas sin cobrar ============ -->
          <section class="tarjeta overflow-hidden lg:col-span-3">
            <header class="px-5 py-4 border-b border-slate-100">
              <div class="flex items-baseline justify-between gap-3">
                <h2 class="font-semibold">Atendidas sin cobrar</h2>
                <span class="text-sm font-semibold tabular-nums"
                      [style.color]="k.atendidas_sin_cobrar > 0 ? advertencia : ''">
                  {{ k.atendidas_sin_cobrar }} de {{ k.atendidas }}
                </span>
              </div>
              <p class="text-sm text-slate-500 mt-0.5">
                Una visita cuenta como cobrada cuando tiene un pago
                <strong>ligado a esa cita</strong>. Un pago suelto suma a los ingresos
                pero no cierra la visita.
              </p>
            </header>

            @if (sinCobrar().length === 0) {
              <app-vacio titulo="Todo cobrado"
                         detalle="No quedan visitas atendidas sin pago en este período." />
            } @else {
              <div class="overflow-x-auto max-h-80">
                <table class="tabla">
                  <thead><tr>
                    <th>Fecha</th><th>Paciente</th><th>Fisioterapeuta</th>
                    <th class="text-right">Cargos</th><th></th>
                  </tr></thead>
                  <tbody>
                    @for (v of sinCobrar(); track v.cita_id) {
                      <tr>
                        <td class="whitespace-nowrap text-sm">
                          {{ v.fecha ? fecha(v.fecha) : '—' }}
                          <span class="block font-mono text-[10px] text-slate-400">
                            {{ v.codigo_referencia }}
                          </span>
                        </td>
                        <td>
                          <span class="text-sm font-medium">{{ v.paciente }}</span>
                          <span class="dpi block">{{ v.dpi_mascara }}</span>
                        </td>
                        <td class="text-sm text-slate-500">{{ v.fisioterapeuta ?? '—' }}</td>
                        <td class="text-right tabular-nums">
                          {{ v.cargos > 0 ? dinero(v.cargos) : '—' }}
                        </td>
                        <td class="text-right">
                          <a [routerLink]="['/panel/pacientes', v.paciente_id]"
                             class="btn-secundario btn-sm">Cobrar</a>
                        </td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
            }
          </section>
        </div>
      }
    </div>
  `,
  styles: [`
    :host { --kpi-acento: #0d9488; }
  `],
})
export class Indicadores {
  private readonly api = inject(IndicadoresService);
  private readonly avisos = inject(AvisosService);

  /** Paleta validada con el script de la guía (todas las comprobaciones pasan). */
  readonly acento = '#0d9488';
  readonly advertencia = '#d97706';
  readonly critico = '#e11d48';

  readonly rangos = [
    { id: 'hoy', etiqueta: 'Hoy' },
    { id: '7', etiqueta: '7 días' },
    { id: '30', etiqueta: '30 días' },
    { id: 'mes', etiqueta: 'Este mes' },
    { id: 'anterior', etiqueta: 'Mes pasado' },
  ];
  readonly granularidades: Array<{ id: Granularidad; etiqueta: string }> = [
    { id: 'day', etiqueta: 'Día' },
    { id: 'week', etiqueta: 'Semana' },
    { id: 'month', etiqueta: 'Mes' },
  ];

  readonly cargando = signal(true);
  readonly desde = signal(sumarDias(hoyIso(), -29));
  readonly hasta = signal(hoyIso());
  readonly granularidad = signal<Granularidad>('day');
  readonly rangoActivo = signal('30');
  readonly resumen = signal<ResumenKpis | null>(null);
  readonly serie = signal<PuntoSerie[]>([]);
  readonly sinCobrar = signal<VisitaSinCobrar[]>([]);

  readonly dinero = moneda;
  readonly fecha = fechaCorta;

  dineroCorto(n: number): string {
    if (n >= 1000) return 'Q' + (n / 1000).toFixed(n >= 10000 ? 0 : 1) + 'k';
    return 'Q' + Math.round(n);
  }

  readonly tiles = computed(() => {
    const k = this.resumen();
    if (!k) return [];
    return [
      {
        etiqueta: 'Pacientes atendidos',
        valor: String(k.pacientes_atendidos),
        pie: `${k.atendidas} cita${k.atendidas === 1 ? '' : 's'} atendida${k.atendidas === 1 ? '' : 's'}`
          + (k.tasa_asistencia !== null ? ` · ${k.tasa_asistencia}% de asistencia` : ''),
        color: '',
      },
      {
        etiqueta: 'Cancelaciones',
        valor: String(k.canceladas + k.rechazadas),
        pie: `${k.canceladas} canceladas · ${k.rechazadas} rechazadas · ${k.ausentes} no asistieron`,
        color: k.canceladas + k.rechazadas > 0 ? this.critico : '',
      },
      {
        etiqueta: 'Sin cobrar',
        valor: String(k.atendidas_sin_cobrar),
        pie: k.tasa_cobro !== null
          ? `${k.atendidas_cobradas} cobradas · ${k.tasa_cobro}% de cobro`
          : 'sin visitas atendidas',
        color: k.atendidas_sin_cobrar > 0 ? this.advertencia : '',
      },
    ];
  });

  readonly maximoSerie = computed(() =>
    Math.max(...this.serie().map((p) => Number(p.ingresos)), 0));

  altura(v: number): number {
    const max = this.maximoSerie();
    return max > 0 ? (Number(v) / max) * 100 : 0;
  }

  /** Tres líneas guía en 0 / mitad / máximo, redondeadas hacia arriba. */
  readonly guias = computed(() => {
    const max = this.maximoSerie();
    if (max <= 0) return [];
    return [
      { valor: max, posicion: 0 },
      { valor: max / 2, posicion: 50 },
    ];
  });

  readonly porMetodo = computed(() => {
    const k = this.resumen();
    if (!k) return [];
    const total = Object.values(k.ingresos_por_metodo ?? {})
      .reduce((s, v) => s + Number(v), 0);
    return Object.entries(k.ingresos_por_metodo ?? {})
      .map(([metodo, monto]) => ({
        metodo,
        monto: Number(monto),
        porcentaje: total > 0 ? Math.round((Number(monto) / total) * 100) : 0,
      }))
      .sort((a, b) => b.monto - a.monto);
  });

  readonly etiquetaGranularidad = computed(() => ({
    day: 'día', week: 'semana', month: 'mes',
  }[this.granularidad()]));

  /** En rangos largos se etiqueta cada n-ésima barra para que no se encimen. */
  mostrarEtiqueta(i: number): boolean {
    const n = this.serie().length;
    const cada = n <= 10 ? 1 : n <= 20 ? 2 : n <= 45 ? 5 : Math.ceil(n / 8);
    return i % cada === 0 || i === n - 1;
  }

  etiquetaEje(iso: string): string {
    const d = new Date(`${iso}T12:00:00`);
    if (this.granularidad() === 'month') {
      return new Intl.DateTimeFormat('es-GT', { month: 'short' }).format(d);
    }
    return new Intl.DateTimeFormat('es-GT', { day: 'numeric', month: 'short' }).format(d);
  }

  etiquetaPeriodo(iso: string): string {
    const d = new Date(`${iso}T12:00:00`);
    if (this.granularidad() === 'month') {
      return new Intl.DateTimeFormat('es-GT', { month: 'long', year: 'numeric' }).format(d);
    }
    if (this.granularidad() === 'week') {
      return 'Semana del ' + new Intl.DateTimeFormat('es-GT', {
        day: 'numeric', month: 'short',
      }).format(d);
    }
    return new Intl.DateTimeFormat('es-GT', {
      weekday: 'short', day: 'numeric', month: 'short',
    }).format(d);
  }

  constructor() { void this.cargar(); }

  private async cargar() {
    this.cargando.set(true);
    try {
      const [k, s, sc] = await Promise.all([
        this.api.resumen(this.desde(), this.hasta()),
        this.api.serie(this.desde(), this.hasta(), this.granularidad()),
        this.api.sinCobrar(this.desde(), this.hasta()),
      ]);
      this.resumen.set(k);
      this.serie.set(s);
      this.sinCobrar.set(sc);
    } catch (e) {
      this.avisos.error(
        e instanceof Error && /insufficient|permission/i.test(e.message)
          ? 'Su rol no permite ver los indicadores.'
          : 'No se pudieron cargar los indicadores.',
      );
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  aplicarRango(id: string) {
    const hoy = hoyIso();
    this.rangoActivo.set(id);
    switch (id) {
      case 'hoy':
        this.desde.set(hoy); this.hasta.set(hoy);
        this.granularidad.set('day');
        break;
      case '7':
        this.desde.set(sumarDias(hoy, -6)); this.hasta.set(hoy);
        this.granularidad.set('day');
        break;
      case '30':
        this.desde.set(sumarDias(hoy, -29)); this.hasta.set(hoy);
        this.granularidad.set('day');
        break;
      case 'mes': {
        this.desde.set(hoy.slice(0, 8) + '01'); this.hasta.set(hoy);
        this.granularidad.set('day');
        break;
      }
      case 'anterior': {
        const d = new Date(`${hoy.slice(0, 8)}01T12:00:00`);
        d.setMonth(d.getMonth() - 1);
        const ini = d.toISOString().slice(0, 10);
        d.setMonth(d.getMonth() + 1);
        d.setDate(0);
        this.desde.set(ini);
        this.hasta.set(d.toISOString().slice(0, 10));
        this.granularidad.set('day');
        break;
      }
    }
    void this.cargar();
  }

  cambiarFecha(cual: 'desde' | 'hasta', e: Event) {
    const v = (e.target as HTMLInputElement).value;
    if (!v) return;
    if (cual === 'desde') this.desde.set(v); else this.hasta.set(v);
    this.rangoActivo.set('');
    void this.cargar();
  }

  cambiarGranularidad(g: Granularidad) {
    this.granularidad.set(g);
    void this.cargar();
  }
}
