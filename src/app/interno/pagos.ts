import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { ClinicaService } from '../core/api/clinica.service';
import { PacientesService } from '../core/api/pacientes.service';
import { MetodoPago, PacienteListado, Pago } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaCorta, hoyIso, moneda, sumarDias } from '../core/util/formato';
import { Cargando, Dialogo, Vacio } from '../shared/ui';

@Component({
  selector: 'app-pagos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Dialogo, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Pagos</h1>
          <p class="text-sm text-slate-500 mt-0.5">
            Registro de cobros. Un pago aplicado no se edita: se anula y se registra otro.
          </p>
        </div>
        <button type="button" class="btn-primario" (click)="abrirNuevo()">Registrar pago</button>
      </header>

      <div class="flex flex-wrap gap-2 mb-4">
        <input class="campo w-40 py-2" type="date" [value]="desde()" (change)="cambiar('desde', $event)">
        <input class="campo w-40 py-2" type="date" [value]="hasta()" (change)="cambiar('hasta', $event)">
        <div class="flex gap-1.5">
          @for (r of rangos; track r.dias) {
            <button type="button" class="btn-secundario btn-sm" (click)="rango(r.dias)">{{ r.etiqueta }}</button>
          }
        </div>
      </div>

      <div class="grid gap-3 sm:grid-cols-3 mb-5">
        <div class="tarjeta p-4">
          <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">Total cobrado</p>
          <p class="mt-1 text-2xl font-bold tabular-nums">{{ dinero(total()) }}</p>
        </div>
        <div class="tarjeta p-4">
          <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">Movimientos</p>
          <p class="mt-1 text-2xl font-bold tabular-nums">{{ activos().length }}</p>
        </div>
        <div class="tarjeta p-4">
          <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">Efectivo</p>
          <p class="mt-1 text-2xl font-bold tabular-nums">{{ dinero(porMetodo('efectivo')) }}</p>
        </div>
      </div>

      @if (cargando()) {
        <app-cargando />
      } @else if (lista().length === 0) {
        <div class="tarjeta"><app-vacio titulo="Sin pagos en el rango seleccionado" /></div>
      } @else {
        <div class="tarjeta overflow-hidden">
          <div class="overflow-x-auto">
            <table class="tabla">
              <thead><tr>
                <th>Fecha</th><th>Paciente</th><th>Concepto</th><th>Método</th>
                <th class="text-right">Monto</th><th>Estado</th><th></th>
              </tr></thead>
              <tbody>
                @for (p of lista(); track p.id) {
                  <tr [class.opacity-50]="p.estado === 'anulado'">
                    <td class="whitespace-nowrap text-sm">{{ fecha(p.fecha) }}</td>
                    <td>
                      <a [routerLink]="['/panel/pacientes', p.paciente_id]"
                         class="text-sm hover:text-marca-700">{{ nombre(p.paciente_id) }}</a>
                    </td>
                    <td class="text-sm">{{ p.descripcion ?? p.referencia ?? '—' }}</td>
                    <td class="text-sm capitalize">{{ p.metodo }}</td>
                    <td class="text-right tabular-nums font-medium">{{ dinero(p.monto) }}</td>
                    <td>
                      <span class="chip" [class]="p.estado === 'pagado'
                        ? 'bg-emerald-50 text-emerald-800 ring-emerald-200'
                        : 'bg-slate-100 text-slate-600 ring-slate-300'">{{ p.estado }}</span>
                    </td>
                    <td class="text-right">
                      @if (p.estado === 'pagado') {
                        <button type="button" class="btn-fantasma btn-sm" (click)="abrirAnular(p)">Anular</button>
                      }
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        </div>
      }
    </div>

    <app-dialogo [(abierto)]="dlgNuevo" titulo="Registrar pago" ancho="lg">
      <div class="space-y-4">
        <div>
          <label class="etiqueta" for="p-pac">Paciente</label>
          <input id="p-pac" class="campo" placeholder="Buscar por nombre o DPI…"
                 [value]="buscaPaciente()" (input)="buscarPaciente($event)">
          @if (candidatos().length) {
            <ul class="mt-1.5 rounded-lg ring-1 ring-slate-200 divide-y divide-slate-100 max-h-48 overflow-y-auto">
              @for (c of candidatos(); track c.id) {
                <li>
                  <button type="button" class="w-full text-left px-3 py-2 hover:bg-slate-50"
                          (click)="elegirPaciente(c)">
                    <span class="text-sm font-medium">{{ c.nombre_completo }}</span>
                    <span class="dpi ml-2">{{ c.dpi_mascara }}</span>
                  </button>
                </li>
              }
            </ul>
          }
          @if (pacienteSel(); as ps) {
            <p class="mt-1.5 text-sm text-marca-700">
              Seleccionado: <strong>{{ ps.nombre_completo }}</strong> ({{ ps.dpi_mascara }})
            </p>
          }
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="etiqueta" for="p-monto">Monto (GTQ)</label>
            <input id="p-monto" class="campo" type="number" min="0.01" step="0.01"
                   [value]="monto()" (input)="monto.set(+$any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="p-met">Método</label>
            <select id="p-met" class="campo" [value]="metodo()"
                    (change)="metodo.set($any($event.target).value)">
              @for (m of metodos; track m) { <option [value]="m">{{ m }}</option> }
            </select>
          </div>
          <div>
            <label class="etiqueta" for="p-ref">Referencia / boleta</label>
            <input id="p-ref" class="campo" [value]="referencia()"
                   (input)="referencia.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="p-desc">Concepto</label>
            <input id="p-desc" class="campo" [value]="descripcion()"
                   (input)="descripcion.set($any($event.target).value)">
          </div>
        </div>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgNuevo.set(false)">Cancelar</button>
        <button type="button" class="btn-primario"
                [disabled]="!pacienteSel() || monto() <= 0 || guardando()"
                (click)="guardar()">Registrar</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgAnular" titulo="Anular pago"
                 subtitulo="El movimiento queda visible, marcado como anulado">
      <div>
        <label class="etiqueta" for="a-mot">Motivo</label>
        <textarea id="a-mot" class="campo" rows="3"
                  (input)="motivoAnulacion.set($any($event.target).value)">{{ motivoAnulacion() }}</textarea>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAnular.set(false)">Volver</button>
        <button type="button" class="btn-peligro"
                [disabled]="motivoAnulacion().trim().length < 3 || guardando()"
                (click)="anular()">Anular</button>
      </div>
    </app-dialogo>
  `,
})
export class Pagos {
  private readonly clinica = inject(ClinicaService);
  private readonly pacientesApi = inject(PacientesService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly metodos: MetodoPago[] = ['efectivo', 'tarjeta', 'transferencia', 'deposito', 'otro'];
  readonly rangos = [
    { dias: 0, etiqueta: 'Hoy' },
    { dias: 7, etiqueta: '7 días' },
    { dias: 30, etiqueta: '30 días' },
  ];

  readonly cargando = signal(true);
  readonly guardando = signal(false);
  readonly lista = signal<Pago[]>([]);
  readonly nombres = signal<Map<string, string>>(new Map());
  readonly desde = signal(sumarDias(hoyIso(), -30));
  readonly hasta = signal(hoyIso());

  readonly dlgNuevo = signal(false);
  readonly dlgAnular = signal(false);
  readonly buscaPaciente = signal('');
  readonly candidatos = signal<PacienteListado[]>([]);
  readonly pacienteSel = signal<PacienteListado | null>(null);
  readonly monto = signal(0);
  readonly metodo = signal<MetodoPago>('efectivo');
  readonly referencia = signal('');
  readonly descripcion = signal('');
  readonly pagoAnular = signal<Pago | null>(null);
  readonly motivoAnulacion = signal('');

  readonly fecha = fechaCorta;
  readonly dinero = moneda;
  private temporizador?: ReturnType<typeof setTimeout>;

  readonly activos = computed(() => this.lista().filter((p) => p.estado === 'pagado'));
  readonly total = computed(() => this.activos().reduce((s, p) => s + Number(p.monto), 0));

  porMetodo(m: MetodoPago): number {
    return this.activos().filter((p) => p.metodo === m).reduce((s, p) => s + Number(p.monto), 0);
  }

  nombre(id: string): string { return this.nombres().get(id) ?? '—'; }

  constructor() { void this.cargar(); }

  private async cargar() {
    this.cargando.set(true);
    try {
      const pagos = await this.clinica.pagos({ desde: this.desde(), hasta: this.hasta() });
      this.lista.set(pagos);
      const ids = [...new Set(pagos.map((p) => p.paciente_id))];
      if (ids.length) {
        const filas = await this.pacientesApi.listar({ limite: 500 });
        this.nombres.set(new Map(filas.map((f) => [f.id, f.nombre_completo])));
      }
    } catch (e) {
      this.avisos.error('No se pudieron cargar los pagos.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  cambiar(cual: 'desde' | 'hasta', e: Event) {
    const v = (e.target as HTMLInputElement).value;
    if (cual === 'desde') this.desde.set(v); else this.hasta.set(v);
    void this.cargar();
  }

  rango(dias: number) {
    this.desde.set(sumarDias(hoyIso(), -dias));
    this.hasta.set(hoyIso());
    void this.cargar();
  }

  abrirNuevo() {
    this.pacienteSel.set(null); this.buscaPaciente.set(''); this.candidatos.set([]);
    this.monto.set(0); this.metodo.set('efectivo');
    this.referencia.set(''); this.descripcion.set('');
    this.dlgNuevo.set(true);
  }

  buscarPaciente(e: Event) {
    const t = (e.target as HTMLInputElement).value;
    this.buscaPaciente.set(t);
    this.pacienteSel.set(null);
    clearTimeout(this.temporizador);
    if (t.trim().length < 3) { this.candidatos.set([]); return; }
    this.temporizador = setTimeout(async () => {
      this.candidatos.set(await this.pacientesApi.listar({ texto: t, limite: 8 }).catch(() => []));
    }, 300);
  }

  elegirPaciente(p: PacienteListado) {
    this.pacienteSel.set(p);
    this.buscaPaciente.set(p.nombre_completo);
    this.candidatos.set([]);
  }

  async guardar() {
    const p = this.pacienteSel();
    if (!p || this.monto() <= 0) return;
    this.guardando.set(true);
    try {
      await this.clinica.registrarPago({
        paciente_id: p.id,
        monto: this.monto(),
        metodo: this.metodo(),
        estado: 'pagado',
        referencia: this.referencia() || null,
        descripcion: this.descripcion() || null,
        registrado_por: this.auth.perfil()!.id,
      });
      this.avisos.exito('Pago registrado.');
      this.dlgNuevo.set(false);
      await this.cargar();
    } catch (e) {
      this.avisos.error('No se pudo registrar el pago.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  abrirAnular(p: Pago) {
    this.pagoAnular.set(p);
    this.motivoAnulacion.set('');
    this.dlgAnular.set(true);
  }

  async anular() {
    const p = this.pagoAnular();
    if (!p) return;
    this.guardando.set(true);
    try {
      await this.clinica.anularPago(p.id, this.motivoAnulacion());
      this.avisos.exito('Pago anulado.');
      this.dlgAnular.set(false);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo anular el pago.');
    } finally {
      this.guardando.set(false);
    }
  }
}
