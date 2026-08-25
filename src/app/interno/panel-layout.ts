import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CitasService } from '../core/api/citas.service';
import { ETIQUETAS_ROL } from '../core/modelos';
import { iniciales } from '../core/util/formato';

interface Entrada {
  ruta: string;
  etiqueta: string;
  icono: string;
  visible: () => boolean;
  contador?: () => number;
}

@Component({
  selector: 'app-panel-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="min-h-dvh flex flex-col lg:flex-row bg-slate-50">

      <!-- Barra superior en móvil -->
      <header class="lg:hidden sticky top-0 z-30 bg-white border-b border-slate-200 no-imprimir">
        <div class="h-14 px-4 flex items-center justify-between">
          <span class="font-semibold tracking-tight">NeoTerapia</span>
          <button type="button" class="btn-fantasma btn-sm" (click)="menu.set(!menu())">
            {{ menu() ? 'Cerrar' : 'Menú' }}
          </button>
        </div>
        @if (menu()) {
          <nav class="px-3 pb-3 grid grid-cols-2 gap-1.5 border-t border-slate-100 pt-3">
            @for (e of entradasVisibles(); track e.ruta) {
              <a [routerLink]="e.ruta" routerLinkActive="bg-marca-50 text-marca-800"
                 class="rounded-lg px-3 py-2 text-sm text-slate-700 hover:bg-slate-100"
                 (click)="menu.set(false)">{{ e.etiqueta }}</a>
            }
          </nav>
        }
      </header>

      <!-- Barra lateral -->
      <aside class="hidden lg:flex lg:flex-col w-60 shrink-0 bg-white border-r border-slate-200 no-imprimir">
        <div class="h-16 px-5 flex items-center gap-2.5 border-b border-slate-100">
          <span class="w-8 h-8 rounded-lg bg-marca-600 grid place-items-center text-white shrink-0">
            <svg viewBox="0 0 24 24" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 12h3l2.5-6 3.5 12 3-9 2 3h4"/>
            </svg>
          </span>
          <span class="font-semibold tracking-tight">NeoTerapia</span>
        </div>

        <nav class="flex-1 p-3 space-y-0.5 overflow-y-auto">
          @for (e of entradasVisibles(); track e.ruta) {
            <a [routerLink]="e.ruta" routerLinkActive="bg-marca-50 text-marca-800 font-medium"
               class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <svg viewBox="0 0 24 24" class="w-4.5 h-4.5 shrink-0" fill="none"
                   stroke="currentColor" stroke-width="1.8" style="width:1.125rem;height:1.125rem">
                <path stroke-linecap="round" stroke-linejoin="round" [attr.d]="e.icono"/>
              </svg>
              <span class="flex-1">{{ e.etiqueta }}</span>
              @if (e.contador && e.contador()! > 0) {
                <span class="min-w-5 h-5 px-1.5 rounded-full bg-marca-600 text-white text-[11px]
                             font-semibold grid place-items-center">{{ e.contador!() }}</span>
              }
            </a>
          }
        </nav>

        <div class="p-3 border-t border-slate-100">
          <div class="flex items-center gap-3 px-2 py-2">
            <span class="w-9 h-9 rounded-full bg-slate-200 text-slate-600 grid place-items-center
                         text-xs font-semibold shrink-0">{{ ini() }}</span>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium truncate">{{ auth.perfil()?.nombre_completo }}</p>
              <p class="text-xs text-slate-500 truncate">{{ rolTexto() }}</p>
            </div>
          </div>
          <div class="mt-1 flex gap-1">
            <a routerLink="/panel/clave" class="btn-fantasma btn-sm flex-1">Contraseña</a>
            <button type="button" class="btn-fantasma btn-sm flex-1" (click)="salir()">Salir</button>
          </div>
        </div>
      </aside>

      <main class="flex-1 min-w-0"><router-outlet /></main>
    </div>
  `,
})
export class PanelLayout {
  readonly auth = inject(AuthService);
  private readonly citas = inject(CitasService);

  readonly menu = signal(false);
  readonly metricas = signal<Record<string, number>>({});

  readonly ini = computed(() => iniciales(this.auth.perfil()?.nombre_completo));
  readonly rolTexto = computed(() => {
    const r = this.auth.rol();
    return r ? ETIQUETAS_ROL[r] : '';
  });

  private readonly entradas: Entrada[] = [
    {
      ruta: '/panel/tablero', etiqueta: 'Tablero', visible: () => true,
      icono: 'M4 6a2 2 0 0 1 2-2h4v6H4V6Zm0 8h6v6H6a2 2 0 0 1-2-2v-4Zm10-10h4a2 2 0 0 1 2 2v4h-6V4Zm0 8h6v6a2 2 0 0 1-2 2h-4v-8Z',
    },
    {
      ruta: '/panel/solicitudes', etiqueta: 'Solicitudes', visible: () => true,
      contador: () => this.metricas()['solicitudes_pendientes'] ?? 0,
      icono: 'M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2M9 5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2m-6 9 2 2 4-4',
    },
    {
      ruta: '/panel/agenda', etiqueta: 'Agenda', visible: () => true,
      icono: 'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2Z',
    },
    {
      ruta: '/panel/pacientes', etiqueta: 'Pacientes', visible: () => true,
      icono: 'M15 19a6 6 0 0 0-12 0M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm12 8a5 5 0 0 0-4-4.9M16 3.1a4 4 0 0 1 0 7.8',
    },
    {
      ruta: '/panel/pagos', etiqueta: 'Pagos', visible: () => this.auth.veFinanzas(),
      icono: 'M3 10h18M3 8a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Zm4 8h4',
    },
    {
      ruta: '/panel/alertas', etiqueta: 'Alertas', visible: () => this.auth.veFinanzas(),
      contador: () => this.metricas()['alertas_pendientes'] ?? 0,
      icono: 'M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z',
    },
    {
      ruta: '/panel/administracion', etiqueta: 'Administración', visible: () => this.auth.esAdmin(),
      contador: () => this.metricas()['duplicados_pendientes'] ?? 0,
      icono: 'M10.3 4.3a1 1 0 0 1 1-.8h1.4a1 1 0 0 1 1 .8l.2 1.3a7 7 0 0 1 1.6.9l1.2-.5a1 1 0 0 1 1.2.4l.7 1.2a1 1 0 0 1-.2 1.3l-1 .8a7 7 0 0 1 0 1.8l1 .8a1 1 0 0 1 .2 1.3l-.7 1.2a1 1 0 0 1-1.2.4l-1.2-.5a7 7 0 0 1-1.6 1l-.2 1.2a1 1 0 0 1-1 .8h-1.4a1 1 0 0 1-1-.8l-.2-1.3a7 7 0 0 1-1.6-.9l-1.2.5a1 1 0 0 1-1.2-.4l-.7-1.2a1 1 0 0 1 .2-1.3l1-.8a7 7 0 0 1 0-1.8l-1-.8a1 1 0 0 1-.2-1.3l.7-1.2a1 1 0 0 1 1.2-.4l1.2.5a7 7 0 0 1 1.6-1l.2-1.2ZM14 12a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z',
    },
  ];

  readonly entradasVisibles = computed(() => this.entradas.filter((e) => e.visible()));

  constructor() {
    void this.refrescar();
    setInterval(() => void this.refrescar(), 60_000);
  }

  private async refrescar() {
    const m = await this.citas.metricas().catch(() => null);
    if (m) this.metricas.set(m);
  }

  salir() { void this.auth.cerrarSesion(); }
}
