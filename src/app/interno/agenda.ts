import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { CitasService } from '../core/api/citas.service';
import { EventoAgenda, Perfil } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaLarga, hoyIso, horaDe, sumarDias } from '../core/util/formato';
import { Cargando, ChipEstado, Vacio } from '../shared/ui';

@Component({
  selector: 'app-agenda',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ChipEstado, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Agenda</h1>
          <p class="text-sm text-slate-500 mt-0.5 capitalize">{{ rangoTexto() }}</p>
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
                <h2 class="font-semibold capitalize text-sm">{{ dia.etiqueta }}</h2>
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
                      </div>
                      <p class="text-xs text-slate-500 mt-0.5 truncate">
                        <span class="dpi">{{ c.dpi_mascara }}</span>
                        @if (c.fisioterapeuta) { · {{ c.fisioterapeuta }} }
                        @if (c.consultorio) { · {{ c.consultorio }} }
                        @if (c.motivo_consulta) { · {{ c.motivo_consulta }} }
                      </p>
                    </div>

                    <div class="flex items-center gap-1.5 shrink-0">
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
  ];

  readonly vista = signal<'dia' | 'semana'>('semana');
  readonly ancla = signal(hoyIso());
  readonly fisioFiltro = signal('');
  readonly fisios = signal<Perfil[]>([]);
  readonly eventos = signal<EventoAgenda[]>([]);
  readonly cargando = signal(true);

  readonly hora = horaDe;

  readonly desde = computed(() => {
    if (this.vista() === 'dia') return this.ancla();
    const d = new Date(`${this.ancla()}T12:00:00`);
    return sumarDias(this.ancla(), -((d.getDay() + 6) % 7)); // lunes
  });
  readonly hasta = computed(() =>
    this.vista() === 'dia' ? this.ancla() : sumarDias(this.desde(), 6),
  );

  readonly rangoTexto = computed(() => {
    if (this.vista() === 'dia') return fechaLarga(`${this.ancla()}T12:00:00`);
    return `${fechaLarga(this.desde() + 'T12:00:00')} — ${fechaLarga(this.hasta() + 'T12:00:00')}`;
  });

  readonly porDia = computed(() => {
    const grupos = new Map<string, EventoAgenda[]>();
    for (const e of this.eventos()) {
      const clave = new Intl.DateTimeFormat('en-CA', {
        year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'America/Guatemala',
      }).format(new Date(e.inicio));
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

  cambiarVista(v: 'dia' | 'semana') { this.vista.set(v); void this.cargar(); }
  cambiarFisio(e: Event) {
    this.fisioFiltro.set((e.target as HTMLSelectElement).value);
    void this.cargar();
  }
  mover(n: number) {
    this.ancla.set(sumarDias(this.ancla(), this.vista() === 'dia' ? n : n * 7));
    void this.cargar();
  }
  irHoy() { this.ancla.set(hoyIso()); void this.cargar(); }

  async atender(c: EventoAgenda) {
    try {
      const r = await this.citas.marcarAsistencia(c.id, true);
      if (r.ok) {
        this.avisos.exito('Cita marcada como atendida.');
        await this.cargar();
      }
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
