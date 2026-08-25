import { ChangeDetectionStrategy, Component, computed, inject, input, model, output } from '@angular/core';
import { AvisosService } from '../core/util/avisos.service';
import { ETIQUETAS_ESTADO, EstadoCita } from '../core/modelos';
import { etiquetaDolor } from '../core/util/formato';

/** Pila de avisos flotantes. Se monta una sola vez, en la raíz. */
@Component({
  selector: 'app-avisos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed bottom-4 right-4 z-50 flex flex-col gap-2 w-[min(23rem,calc(100vw-2rem))] no-imprimir">
      @for (a of avisos.lista(); track a.id) {
        <div class="animar-entrada flex items-start gap-3 rounded-lg px-4 py-3 text-sm shadow-lg ring-1"
             [class]="clases(a.tipo)" role="status">
          <span class="flex-1">{{ a.texto }}</span>
          <button type="button" class="opacity-60 hover:opacity-100 leading-none text-lg"
                  (click)="avisos.cerrar(a.id)" aria-label="Cerrar">&times;</button>
        </div>
      }
    </div>
  `,
})
export class Avisos {
  readonly avisos = inject(AvisosService);
  clases(tipo: string): string {
    if (tipo === 'exito') return 'bg-emerald-600 text-white ring-emerald-700';
    if (tipo === 'error') return 'bg-rose-600 text-white ring-rose-700';
    return 'bg-slate-800 text-white ring-slate-900';
  }
}

/** Etiqueta de color por estado de cita. */
@Component({
  selector: 'app-chip-estado',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span [class]="'chip-' + estado()">{{ texto() }}</span>`,
})
export class ChipEstado {
  readonly estado = input.required<EstadoCita>();
  readonly texto = computed(() => ETIQUETAS_ESTADO[this.estado()] ?? this.estado());
}

/** Modal genérico. */
@Component({
  selector: 'app-dialogo',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (abierto()) {
      <div class="fixed inset-0 z-40 flex items-end sm:items-center justify-center p-0 sm:p-4 no-imprimir">
        <div class="absolute inset-0 bg-slate-900/40 backdrop-blur-[1px]" (click)="cerrarSiSePuede()"></div>
        <div class="relative animar-entrada w-full bg-white shadow-xl
                    rounded-t-2xl sm:rounded-xl max-h-[92vh] overflow-y-auto"
             [class]="anchoClase()"
             role="dialog" aria-modal="true">
          <header class="flex items-start justify-between gap-4 px-5 sm:px-6 py-4 border-b border-slate-200 sticky top-0 bg-white rounded-t-2xl sm:rounded-t-xl">
            <div>
              <h2 class="text-base font-semibold">{{ titulo() }}</h2>
              @if (subtitulo()) { <p class="text-sm text-slate-500 mt-0.5">{{ subtitulo() }}</p> }
            </div>
            <button type="button" class="text-slate-400 hover:text-slate-700 text-2xl leading-none -mt-1"
                    (click)="cerrarSiSePuede()" aria-label="Cerrar">&times;</button>
          </header>
          <div class="px-5 sm:px-6 py-5"><ng-content /></div>
          <footer class="px-5 sm:px-6 py-4 border-t border-slate-200 bg-slate-50 rounded-b-xl">
            <ng-content select="[acciones]" />
          </footer>
        </div>
      </div>
    }
  `,
})
export class Dialogo {
  readonly abierto = model(false);
  readonly titulo = input('');
  readonly subtitulo = input('');
  readonly ancho = input<'sm' | 'md' | 'lg' | 'xl'>('md');
  readonly bloqueado = input(false);
  readonly cerrado = output<void>();

  readonly anchoClase = computed(() => ({
    sm: 'sm:max-w-md', md: 'sm:max-w-lg', lg: 'sm:max-w-2xl', xl: 'sm:max-w-4xl',
  })[this.ancho()]);

  cerrarSiSePuede(): void {
    if (this.bloqueado()) return;
    this.abierto.set(false);
    this.cerrado.emit();
  }
}

/** Escala visual analógica del dolor, 0-10. */
@Component({
  selector: 'app-escala-dolor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div>
      <div class="flex items-center justify-between mb-1.5">
        <span class="text-sm text-slate-600">{{ titulo() }}</span>
        <span class="text-sm font-semibold" [style.color]="colorActual()">
          {{ valor() }}/10 · {{ nombre() }}
        </span>
      </div>
      <div class="flex gap-1">
        @for (n of niveles; track n) {
          <button type="button"
                  class="flex-1 h-8 rounded text-xs font-medium transition-all ring-1 ring-inset"
                  [style.background]="valor() >= n ? color(n) : '#f1f5f9'"
                  [style.color]="valor() >= n && n >= 5 ? '#fff' : '#475569'"
                  [class.ring-slate-900]="valor() === n"
                  [class.ring-slate-200]="valor() !== n"
                  [attr.aria-label]="'Nivel ' + n"
                  [attr.aria-pressed]="valor() === n"
                  (click)="valor.set(n)">{{ n }}</button>
        }
      </div>
    </div>
  `,
})
export class EscalaDolor {
  readonly valor = model(0);
  readonly titulo = input('Nivel de dolor');
  readonly niveles = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  readonly nombre = computed(() => etiquetaDolor(this.valor()));
  readonly colorActual = computed(() => this.color(this.valor()));
  color(n: number): string {
    if (n === 0) return '#94a3b8';
    if (n <= 2) return '#4ade80';
    if (n <= 4) return '#facc15';
    if (n <= 6) return '#fb923c';
    if (n <= 8) return '#f43f5e';
    return '#b91c1c';
  }
}

/** Estado vacío con ilustración mínima. */
@Component({
  selector: 'app-vacio',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="text-center py-12 px-6">
      <div class="mx-auto w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center mb-3">
        <svg viewBox="0 0 24 24" class="w-6 h-6 text-slate-400" fill="none" stroke="currentColor" stroke-width="1.6">
          <path stroke-linecap="round" stroke-linejoin="round"
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5.6a1 1 0 0 1 .7.3l4.4 4.4a1 1 0 0 1 .3.7V19a2 2 0 0 1-2 2Z"/>
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-700">{{ titulo() }}</p>
      @if (detalle()) { <p class="text-sm text-slate-500 mt-1 max-w-sm mx-auto">{{ detalle() }}</p> }
      <div class="mt-4"><ng-content /></div>
    </div>
  `,
})
export class Vacio {
  readonly titulo = input('No hay nada por aquí');
  readonly detalle = input('');
}

/** Indicador de carga en línea. */
@Component({
  selector: 'app-cargando',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex items-center justify-center gap-2 py-8 text-sm text-slate-500">
      <svg class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" class="opacity-25"/>
        <path d="M22 12a10 10 0 0 0-10-10" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
      </svg>
      {{ texto() }}
    </div>
  `,
})
export class Cargando {
  readonly texto = input('Cargando…');
}
