import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CitasService } from '../core/api/citas.service';
import { CitaListado, EventoAgenda } from '../core/modelos';
import { fechaLarga, haceCuanto, hoyIso, horaCorta } from '../core/util/formato';
import { Cargando, ChipEstado, Vacio } from '../shared/ui';

@Component({
  selector: 'app-tablero',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ChipEstado, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="mb-6">
        <h1 class="text-2xl font-bold tracking-tight">
          {{ saludo() }}, {{ primerNombre() }}
        </h1>
        <p class="text-sm text-slate-500 mt-0.5 first-letter:uppercase">{{ hoyTexto }}</p>
      </header>

      <!-- Indicadores -->
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        @for (t of tarjetas(); track t.etiqueta) {
          <a [routerLink]="t.ruta" class="tarjeta p-4 hover:ring-marca-300 transition-shadow">
            <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">{{ t.etiqueta }}</p>
            <p class="mt-1.5 text-3xl font-bold tabular-nums"
               [class.text-amber-600]="t.alerta && t.valor > 0">{{ t.valor }}</p>
            @if (t.pie) { <p class="mt-0.5 text-xs text-slate-500">{{ t.pie }}</p> }
          </a>
        }
      </div>

      <div class="mt-6 grid gap-6 lg:grid-cols-5">
        <!-- Agenda de hoy -->
        <section class="lg:col-span-3 tarjeta">
          <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
            <h2 class="font-semibold">Agenda de hoy</h2>
            <a routerLink="/panel/agenda" class="text-sm text-marca-700 hover:underline">Ver agenda</a>
          </header>

          @if (cargando()) {
            <app-cargando />
          } @else if (agendaHoy().length === 0) {
            <app-vacio titulo="No hay citas confirmadas para hoy"
                       detalle="Cuando confirme solicitudes, aparecerán aquí." />
          } @else {
            <ul class="divide-y divide-slate-100">
              @for (c of agendaHoy(); track c.id) {
                <li class="px-5 py-3 flex items-center gap-4">
                  <div class="w-1 h-10 rounded-full shrink-0" [style.background]="c.color"></div>
                  <div class="w-16 shrink-0">
                    <p class="text-sm font-semibold tabular-nums">{{ hora(c.inicio) }}</p>
                  </div>
                  <div class="min-w-0 flex-1">
                    <a [routerLink]="['/panel/pacientes', c.paciente_id]"
                       class="text-sm font-medium hover:text-marca-700 truncate block">{{ c.paciente }}</a>
                    <p class="text-xs text-slate-500 truncate">
                      {{ c.fisioterapeuta ?? 'Sin asignar' }}
                      @if (c.es_primera_vez) { <span class="ml-1.5 chip-neutro">1.ª visita</span> }
                    </p>
                  </div>
                  <app-chip-estado [estado]="c.estado" />
                </li>
              }
            </ul>
          }
        </section>

        <!-- Solicitudes recientes -->
        <section class="lg:col-span-2 tarjeta">
          <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
            <h2 class="font-semibold">Solicitudes por atender</h2>
            <a routerLink="/panel/solicitudes" class="text-sm text-marca-700 hover:underline">Ver todas</a>
          </header>

          @if (cargando()) {
            <app-cargando />
          } @else if (pendientes().length === 0) {
            <app-vacio titulo="Todo al día" detalle="No hay solicitudes sin revisar." />
          } @else {
            <ul class="divide-y divide-slate-100">
              @for (s of pendientes(); track s.id) {
                <li class="px-5 py-3">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <p class="text-sm font-medium truncate">{{ s.nombre_completo }}</p>
                      <p class="text-xs text-slate-500">
                        {{ s.fecha_solicitada }}
                        @if (s.hora_solicitada) { · {{ s.hora_solicitada.slice(0,5) }} }
                      </p>
                    </div>
                    @if (s.alertas_pendientes > 0) {
                      <span class="chip bg-amber-50 text-amber-800 ring-amber-200 shrink-0">
                        {{ s.alertas_pendientes }} alerta{{ s.alertas_pendientes > 1 ? 's' : '' }}
                      </span>
                    }
                  </div>
                  <p class="mt-1 text-xs text-slate-400">{{ cuando(s.creado_en) }}</p>
                </li>
              }
            </ul>
          }
        </section>
      </div>
    </div>
  `,
})
export class Tablero {
  private readonly citas = inject(CitasService);
  readonly auth = inject(AuthService);

  readonly cargando = signal(true);
  readonly metricas = signal<Record<string, number>>({});
  readonly agendaHoy = signal<EventoAgenda[]>([]);
  readonly pendientes = signal<CitaListado[]>([]);

  readonly hoyTexto = fechaLarga(new Date().toISOString());
  readonly hora = horaCorta;
  readonly cuando = haceCuanto;

  readonly primerNombre = computed(
    () => this.auth.perfil()?.nombre_completo.split(' ')[0] ?? '',
  );

  readonly saludo = computed(() => {
    const h = new Date().getHours();
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  });

  readonly tarjetas = computed(() => {
    const m = this.metricas();
    const base = [
      { etiqueta: 'Solicitudes', valor: m['solicitudes_pendientes'] ?? 0, pie: 'sin revisar', ruta: '/panel/solicitudes', alerta: true },
      { etiqueta: 'Citas hoy', valor: m['citas_hoy'] ?? 0, pie: 'confirmadas', ruta: '/panel/agenda', alerta: false },
      { etiqueta: 'Pacientes', valor: m['pacientes_activos'] ?? 0, pie: 'activos', ruta: '/panel/pacientes', alerta: false },
    ];
    if (this.auth.veClinico()) {
      base.push({
        etiqueta: 'Notas sin firmar', valor: m['sesiones_sin_firmar'] ?? 0,
        pie: 'pendientes de cierre', ruta: '/panel/agenda', alerta: true,
      });
    } else {
      base.push({
        etiqueta: 'Alertas', valor: m['alertas_pendientes'] ?? 0,
        pie: 'requieren revisión', ruta: '/panel/alertas', alerta: true,
      });
    }
    return base;
  });

  constructor() {
    void this.cargar();
  }

  private async cargar() {
    this.cargando.set(true);
    const hoy = hoyIso();
    const propio = this.auth.esFisio() ? this.auth.perfil()!.id : null;
    const [m, agenda, sols] = await Promise.all([
      this.citas.metricas().catch(() => ({})),
      this.citas.agenda(hoy, hoy, propio).catch(() => []),
      this.citas.listar({ estados: ['solicitada'], limite: 6 }).catch(() => []),
    ]);
    this.metricas.set(m as Record<string, number>);
    this.agendaHoy.set(agenda);
    this.pendientes.set(sols);
    this.cargando.set(false);
  }
}
