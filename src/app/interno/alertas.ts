import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { PacientesService } from '../core/api/pacientes.service';
import { Alerta, ETIQUETAS_ALERTA } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaHora, haceCuanto } from '../core/util/formato';
import { Cargando, Vacio } from '../shared/ui';

@Component({
  selector: 'app-alertas',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-5xl mx-auto">
      <header class="mb-5">
        <h1 class="text-2xl font-bold tracking-tight">Alertas administrativas</h1>
        <p class="text-sm text-slate-500 mt-0.5">
          Casos que el sistema no puede resolver solo: nombres que no coinciden con el DPI,
          contactos distintos, fichas parecidas.
        </p>
      </header>

      <div class="flex gap-1 p-1 bg-slate-100 rounded-lg w-fit mb-5">
        @for (f of filtros; track f.id) {
          <button type="button" class="px-4 py-1.5 text-sm rounded-md transition-colors"
                  [class]="filtro() === f.id ? 'bg-white shadow-sm font-medium' : 'text-slate-500'"
                  (click)="cambiar(f.id)">{{ f.etiqueta }}</button>
        }
      </div>

      @if (cargando()) {
        <app-cargando />
      } @else if (lista().length === 0) {
        <div class="tarjeta">
          <app-vacio titulo="Nada pendiente" detalle="No hay alertas en esta vista." />
        </div>
      } @else {
        <ul class="space-y-3">
          @for (a of lista(); track a.id) {
            <li class="tarjeta p-4 sm:p-5">
              <div class="flex items-start gap-3">
                <span class="mt-0.5 w-2.5 h-2.5 rounded-full shrink-0"
                      [class]="a.severidad === 3 ? 'bg-rose-500' : a.severidad === 2 ? 'bg-amber-500' : 'bg-slate-400'"></span>
                <div class="min-w-0 flex-1">
                  <p class="font-medium">{{ a.titulo }}</p>
                  <p class="text-xs text-slate-500 mt-0.5">
                    {{ etiqueta(a.tipo) }} · {{ cuando(a.creado_en) }} · {{ fechaYHora(a.creado_en) }}
                  </p>

                  @if (campos(a.detalle).length) {
                    <dl class="mt-2.5 grid gap-x-6 gap-y-1 sm:grid-cols-2 text-sm bg-slate-50 rounded-lg p-3">
                      @for (d of campos(a.detalle); track d.k) {
                        <div class="flex gap-2">
                          <dt class="text-slate-500 shrink-0">{{ d.k }}:</dt>
                          <dd class="text-slate-800 break-words">{{ d.v }}</dd>
                        </div>
                      }
                    </dl>
                  }

                  <div class="mt-3 flex flex-wrap gap-2">
                    @if (a.paciente_id) {
                      <a [routerLink]="['/panel/pacientes', a.paciente_id]" class="btn-secundario btn-sm">
                        Abrir ficha
                      </a>
                    }
                    @if (a.estado === 'pendiente') {
                      <button type="button" class="btn-fantasma btn-sm" (click)="resolver(a, 'revisada')">
                        Marcar revisada
                      </button>
                      <button type="button" class="btn-fantasma btn-sm" (click)="resolver(a, 'descartada')">
                        Descartar
                      </button>
                    } @else {
                      <span class="chip-neutro">{{ a.estado }}</span>
                    }
                  </div>
                </div>
              </div>
            </li>
          }
        </ul>
      }
    </div>
  `,
})
export class Alertas {
  private readonly pacientes = inject(PacientesService);
  private readonly avisos = inject(AvisosService);

  readonly filtros = [
    { id: 'pendiente' as const, etiqueta: 'Pendientes' },
    { id: 'revisada' as const, etiqueta: 'Revisadas' },
    { id: 'todas' as const, etiqueta: 'Todas' },
  ];

  readonly filtro = signal<'pendiente' | 'revisada' | 'todas'>('pendiente');
  readonly lista = signal<Alerta[]>([]);
  readonly cargando = signal(true);

  readonly cuando = haceCuanto;
  readonly fechaYHora = fechaHora;

  constructor() { void this.cargar(); }

  private async cargar() {
    this.cargando.set(true);
    try {
      this.lista.set(await this.pacientes.alertas(this.filtro()));
    } catch {
      this.avisos.error('No se pudieron cargar las alertas.');
    } finally {
      this.cargando.set(false);
    }
  }

  cambiar(f: 'pendiente' | 'revisada' | 'todas') { this.filtro.set(f); void this.cargar(); }

  etiqueta(t: Alerta['tipo']): string { return ETIQUETAS_ALERTA[t] ?? t; }

  campos(d: Record<string, unknown>): Array<{ k: string; v: string }> {
    return Object.entries(d ?? {}).map(([k, v]) => ({
      k: k.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()),
      v: String(v),
    }));
  }

  async resolver(a: Alerta, estado: 'revisada' | 'descartada') {
    try {
      await this.pacientes.resolverAlerta(a.id, estado);
      this.avisos.exito(estado === 'revisada' ? 'Alerta marcada como revisada.' : 'Alerta descartada.');
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo actualizar la alerta.');
    }
  }
}
