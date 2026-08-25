import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { CitasService } from '../core/api/citas.service';
import { EventoAgenda, Perfil } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaLarga, hoyIso, horaDe, sumarDias } from '../core/util/formato';
import { Cargando, ChipEstado, Dialogo, Vacio } from '../shared/ui';

type Vista = 'dia' | 'semana' | 'mes';

@Component({
  selector: 'app-agenda',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ChipEstado, Cargando, Dialogo, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Agenda</h1>
          <p class="text-sm text-slate-500 mt-0.5 first-letter:uppercase">{{ rangoTexto() }}</p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          @if (!auth.esFisio()) {
            <select class="campo w-48 py-2" [value]="fisioFiltro()"
                    (change)="cambiarFisio($event)">
              <option value="">Todos los fisioterapeutas</option>
              @for (f of fisios(); track f.id) {
                <option [value]="f.id">{{ f.nombre_completo }}</option>
              }
            </select>
          }
          <div class="flex rounded-lg ring-1 ring-slate-300 overflow-hidden">
            @for (v of vistas; track v.id) {
              <button type="button" class="px-3 py-2 text-sm transition-colors"
                      [class]="vista() === v.id ? 'bg-marca-600 text-white' : 'bg-white hover:bg-slate-50'"
                      (click)="cambiarVista(v.id)">{{ v.etiqueta }}</button>
            }
          </div>
          <div class="flex items-center gap-1">
            <button type="button" class="btn-secundario btn-sm" (click)="mover(-1)">‹</button>
            <button type="button" class="btn-secundario btn-sm" (click)="irHoy()">Hoy</button>
            <button type="button" class="btn-secundario btn-sm" (click)="mover(1)">›</button>
          </div>
        </div>
      </header>

      @if (cargando()) {
        <app-cargando />

      <!-- ---------- Vista de mes ---------- -->
      } @else if (vista() === 'mes') {
        <div class="tarjeta overflow-hidden">
          <div class="grid grid-cols-7 border-b border-slate-200 bg-slate-50">
            @for (d of diasSemana; track d) {
              <div class="px-2 py-2 text-center text-xs font-semibold uppercase tracking-wide text-slate-500">
                {{ d }}
              </div>
            }
          </div>
          <div class="grid grid-cols-7">
            @for (c of celdasMes(); track c.fecha) {
              <button type="button"
                      class="relative min-h-24 sm:min-h-28 border-b border-r border-slate-100 p-1.5
                             text-left align-top transition-colors hover:bg-slate-50 focus:z-10"
                      [class.bg-slate-50]="!c.delMes"
                      [class.opacity-45]="!c.delMes"
                      (click)="abrirDia(c.fecha)">
                <span class="inline-flex items-center justify-center w-6 h-6 rounded-full text-xs font-medium"
                      [class]="c.esHoy ? 'bg-marca-600 text-white' : 'text-slate-600'">
                  {{ c.dia }}
                </span>

                @if (c.citas.length) {
                  <div class="mt-1 space-y-0.5">
                    @for (e of c.citas.slice(0, 3); track e.id) {
                      <span class="flex items-center gap-1 rounded px-1 py-0.5 text-[11px] leading-tight"
                            [style.background]="e.color + '1a'">
                        <span class="w-1.5 h-1.5 rounded-full shrink-0" [style.background]="e.color"></span>
                        <span class="tabular-nums text-slate-500 shrink-0">{{ hora(e.inicio) }}</span>
                        <span class="truncate text-slate-700">{{ e.paciente }}</span>
                      </span>
                    }
                    @if (c.citas.length > 3) {
                      <span class="block px-1 text-[11px] text-slate-400">
                        +{{ c.citas.length - 3 }} más
                      </span>
                    }
                  </div>
                }
              </button>
            }
          </div>
        </div>
        <p class="mt-3 text-xs text-slate-400">
          Toque un día para abrir su detalle.
        </p>

      } @else if (eventos().length === 0) {
        <div class="tarjeta">
          <app-vacio titulo="No hay citas en este rango"
                     detalle="Confirme solicitudes para que aparezcan en la agenda." />
        </div>
      } @else {
        <div class="space-y-5">
          @for (dia of porDia(); track dia.fecha) {
            <section class="tarjeta overflow-hidden">
              <header class="px-5 py-3 bg-slate-50 border-b border-slate-200 flex items-center justify-between">
                <h2 class="font-semibold first-letter:uppercase text-sm">{{ dia.etiqueta }}</h2>
                <span class="text-xs text-slate-500">{{ dia.citas.length }} cita{{ dia.citas.length > 1 ? 's' : '' }}</span>
              </header>
              <ul class="divide-y divide-slate-100">
                @for (c of dia.citas; track c.id) {
                  <li class="px-4 sm:px-5 py-3 flex items-center gap-4 hover:bg-slate-50/70">
                    <div class="w-1.5 self-stretch rounded-full shrink-0 min-h-10"
                         [style.background]="c.color"></div>
                    <div class="w-20 shrink-0">
                      <p class="text-sm font-semibold tabular-nums">{{ hora(c.inicio) }}</p>
                      <p class="text-xs text-slate-400 tabular-nums">a {{ hora(c.fin) }}</p>
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-2 flex-wrap">
                        <a [routerLink]="['/panel/pacientes', c.paciente_id]"
                           class="text-sm font-medium hover:text-marca-700">{{ c.paciente }}</a>
                        <app-chip-estado [estado]="c.estado" />
                        @if (c.es_primera_vez) { <span class="chip-neutro">1.ª visita</span> }
                        @if (c.sesion_id && !c.firmada_en) {
                          <span class="chip bg-amber-50 text-amber-800 ring-amber-200">Nota sin firmar</span>
                        }
                        @if (!c.fisioterapeuta_id) {
                          <span class="chip bg-slate-100 text-slate-600 ring-slate-300">Sin asignar</span>
                        }
                      </div>
                      <p class="text-xs text-slate-500 mt-0.5 truncate">
                        <span class="dpi">{{ c.dpi_mascara }}</span>
                        @if (c.fisioterapeuta) { · {{ c.fisioterapeuta }} }
                        @if (c.consultorio) { · {{ c.consultorio }} }
                        @if (c.motivo_consulta) { · {{ c.motivo_consulta }} }
                      </p>
                    </div>

                    <div class="flex items-center gap-1.5 shrink-0">
                      @if (!c.fisioterapeuta_id && auth.coordina() && c.estado === 'confirmada') {
                        <button type="button" class="btn-secundario btn-sm"
                                (click)="abrirAsignar(c)">Asignar</button>
                      }
                      @if (c.estado === 'confirmada') {
                        <button type="button" class="btn-secundario btn-sm"
                                (click)="atender(c)">Atender</button>
                        <button type="button" class="btn-fantasma btn-sm"
                                (click)="ausente(c)">No asistió</button>
                      }
                      @if (c.sesion_id && auth.veClinico()) {
                        <a [routerLink]="['/panel/sesiones', c.sesion_id]" class="btn-secundario btn-sm">
                          {{ c.firmada_en ? 'Ver nota' : 'Nota clínica' }}
                        </a>
                      }
                    </div>
                  </li>
                }
              </ul>
            </section>
          }
        </div>
      }
    </div>

    <app-dialogo [(abierto)]="dlgAsignar" titulo="Asignar fisioterapeuta"
                 [subtitulo]="citaAsignar()?.paciente ?? ''">
      <div class="space-y-3">
        <p class="text-sm text-slate-600">
          Al paciente no se le avisa nada: la cita sigue a la misma hora, solo queda
          registrado quién la atiende.
        </p>
        <div>
          <label class="etiqueta" for="asig">Fisioterapeuta</label>
          <select id="asig" class="campo" [value]="fisioAsignar()"
                  (change)="fisioAsignar.set($any($event.target).value)">
            <option value="">Sin asignar</option>
            @for (f of fisios(); track f.id) {
              <option [value]="f.id">{{ f.nombre_completo }}</option>
            }
          </select>
        </div>
        @if (errorAsignar()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorAsignar() }}
          </p>
        }
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAsignar.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="guardando()"
                (click)="guardarAsignacion()">Guardar</button>
      </div>
    </app-dialogo>
  `,
})
export class Agenda {
  private readonly citas = inject(CitasService);
  private readonly catalogos = inject(CatalogosService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly vistas = [
    { id: 'dia' as const, etiqueta: 'Día' },
    { id: 'semana' as const, etiqueta: 'Semana' },
    { id: 'mes' as const, etiqueta: 'Mes' },
  ];
  readonly diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  readonly vista = signal<Vista>('semana');
  readonly ancla = signal(hoyIso());
  readonly fisioFiltro = signal('');
  readonly fisios = signal<Perfil[]>([]);
  readonly eventos = signal<EventoAgenda[]>([]);
  readonly cargando = signal(true);
  readonly guardando = signal(false);
  readonly dlgAsignar = signal(false);
  readonly citaAsignar = signal<EventoAgenda | null>(null);
  readonly fisioAsignar = signal('');
  readonly errorAsignar = signal('');

  readonly hora = horaDe;

  /** Lunes de la semana que contiene `f`. */
  private lunesDe(f: string): string {
    const d = new Date(`${f}T12:00:00`);
    return sumarDias(f, -((d.getDay() + 6) % 7));
  }

  readonly desde = computed(() => {
    switch (this.vista()) {
      case 'dia': return this.ancla();
      case 'semana': return this.lunesDe(this.ancla());
      // El mes se carga completo pero se pinta desde el lunes de su primera
      // semana, para que la cuadrícula no arranque a media fila.
      case 'mes': return this.lunesDe(this.ancla().slice(0, 8) + '01');
    }
  });

  readonly hasta = computed(() => {
    switch (this.vista()) {
      case 'dia': return this.ancla();
      case 'semana': return sumarDias(this.desde(), 6);
      case 'mes': return sumarDias(this.desde(), 41);   // 6 semanas cubren cualquier mes
    }
  });

  readonly rangoTexto = computed(() => {
    if (this.vista() === 'dia') return fechaLarga(`${this.ancla()}T12:00:00`);
    if (this.vista() === 'mes') {
      return new Intl.DateTimeFormat('es-GT', {
        month: 'long', year: 'numeric', timeZone: 'America/Guatemala',
      }).format(new Date(`${this.ancla()}T12:00:00`));
    }
    return `${fechaLarga(this.desde() + 'T12:00:00')} — ${fechaLarga(this.hasta() + 'T12:00:00')}`;
  });

  /** Cuadrícula de 6×7 para la vista de mes. */
  readonly celdasMes = computed(() => {
    const mes = this.ancla().slice(0, 7);
    const hoy = hoyIso();
    const porFecha = new Map<string, EventoAgenda[]>();
    for (const e of this.eventos()) {
      const clave = this.claveFecha(e.inicio);
      porFecha.set(clave, [...(porFecha.get(clave) ?? []), e]);
    }
    return Array.from({ length: 42 }, (_, i) => {
      const fecha = sumarDias(this.desde(), i);
      return {
        fecha,
        dia: Number(fecha.slice(8, 10)),
        delMes: fecha.slice(0, 7) === mes,
        esHoy: fecha === hoy,
        citas: porFecha.get(fecha) ?? [],
      };
    });
  });

  private claveFecha(iso: string): string {
    return new Intl.DateTimeFormat('en-CA', {
      year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'America/Guatemala',
    }).format(new Date(iso));
  }

  readonly porDia = computed(() => {
    const grupos = new Map<string, EventoAgenda[]>();
    for (const e of this.eventos()) {
      const clave = this.claveFecha(e.inicio);
      grupos.set(clave, [...(grupos.get(clave) ?? []), e]);
    }
    return [...grupos.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([fecha, citas]) => ({
        fecha,
        etiqueta: fechaLarga(`${fecha}T12:00:00`),
        citas,
      }));
  });

  constructor() {
    void this.catalogos.fisioterapeutas().then((f) => this.fisios.set(f));
    void this.cargar();
  }

  private async cargar() {
    this.cargando.set(true);
    try {
      const propio = this.auth.esFisio() ? this.auth.perfil()!.id : (this.fisioFiltro() || null);
      this.eventos.set(await this.citas.agenda(this.desde(), this.hasta(), propio));
    } catch (e) {
      this.avisos.error('No se pudo cargar la agenda.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  cambiarVista(v: Vista) { this.vista.set(v); void this.cargar(); }

  cambiarFisio(e: Event) {
    this.fisioFiltro.set((e.target as HTMLSelectElement).value);
    void this.cargar();
  }

  mover(n: number) {
    if (this.vista() === 'mes') {
      const d = new Date(`${this.ancla().slice(0, 8)}01T12:00:00`);
      d.setMonth(d.getMonth() + n);
      this.ancla.set(d.toISOString().slice(0, 10));
    } else {
      this.ancla.set(sumarDias(this.ancla(), this.vista() === 'dia' ? n : n * 7));
    }
    void this.cargar();
  }

  irHoy() { this.ancla.set(hoyIso()); void this.cargar(); }

  /** Desde la cuadrícula del mes se salta al detalle de ese día. */
  abrirDia(fecha: string) {
    this.ancla.set(fecha);
    this.vista.set('dia');
    void this.cargar();
  }

  abrirAsignar(c: EventoAgenda) {
    this.citaAsignar.set(c);
    this.fisioAsignar.set(c.fisioterapeuta_id ?? '');
    this.errorAsignar.set('');
    this.dlgAsignar.set(true);
  }

  async guardarAsignacion() {
    const c = this.citaAsignar();
    if (!c) return;
    this.guardando.set(true);
    this.errorAsignar.set('');
    try {
      const r = await this.citas.asignarFisioterapeuta(c.id, this.fisioAsignar() || null);
      if (!r.ok) {
        this.errorAsignar.set(r.mensaje ?? 'No se pudo asignar.');
        return;
      }
      this.avisos.exito('Fisioterapeuta asignado.');
      this.dlgAsignar.set(false);
      await this.cargar();
    } catch {
      this.errorAsignar.set('No se pudo asignar el fisioterapeuta.');
    } finally {
      this.guardando.set(false);
    }
  }

  async atender(c: EventoAgenda) {
    try {
      const r = await this.citas.marcarAsistencia(c.id, true);
      if (!r.ok) {
        this.avisos.error(r.mensaje
          ?? 'Asigne un fisioterapeuta antes de marcarla como atendida.');
        return;
      }
      this.avisos.exito('Cita marcada como atendida.');
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo registrar la asistencia.');
    }
  }

  async ausente(c: EventoAgenda) {
    try {
      await this.citas.marcarAsistencia(c.id, false);
      this.avisos.info('Registrada como inasistencia.');
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo registrar la inasistencia.');
    }
  }
}
