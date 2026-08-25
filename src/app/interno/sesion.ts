import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { ClinicaService } from '../core/api/clinica.service';
import { AreaMarcada, SesionDetalle, Tratamiento } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaHora, fechaCorta, horaCorta, moneda } from '../core/util/formato';
import { MapaCorporal } from '../shared/mapa-corporal';
import { Cargando, Dialogo, EscalaDolor, Vacio } from '../shared/ui';

@Component({
  selector: 'app-sesion',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, MapaCorporal, EscalaDolor, Dialogo, Cargando, Vacio],
  template: `
    @if (cargando()) {
      <app-cargando texto="Abriendo la sesión…" />
    } @else if (!sesion()) {
      <div class="p-8"><app-vacio titulo="No se encontró la sesión" /></div>
    } @else {
      <div class="p-4 sm:p-6 lg:p-8 max-w-6xl mx-auto pb-28">

        <header class="flex flex-wrap items-start justify-between gap-4 mb-5">
          <div>
            <p class="text-sm text-slate-500">
              <a [routerLink]="['/panel/pacientes', sesion()!.paciente_id]"
                 class="hover:text-marca-700">{{ sesion()!.paciente }}</a>
              · <span class="dpi">{{ sesion()!.dpi_mascara }}</span>
            </p>
            <h1 class="text-2xl font-bold tracking-tight mt-0.5">Nota clínica</h1>
            <p class="text-sm text-slate-500 mt-0.5">
              {{ fechaYHora(sesion()!.inicio) }} · {{ sesion()!.fisioterapeuta }}
              · <span class="font-mono text-xs">{{ sesion()!.codigo_referencia }}</span>
            </p>
          </div>
          <div class="flex items-center gap-2">
            @if (firmada()) {
              <span class="chip bg-emerald-50 text-emerald-800 ring-emerald-200">
                Firmada {{ fecha(sesion()!.firmada_en) }}
              </span>
              <button type="button" class="btn-secundario btn-sm" (click)="dlgAdenda.set(true)">
                Agregar adenda
              </button>
            } @else {
              <span class="chip bg-amber-50 text-amber-800 ring-amber-200">Borrador</span>
            }
            <button type="button" class="btn-fantasma btn-sm no-imprimir" (click)="imprimir()">Imprimir</button>
          </div>
        </header>

        @if (firmada()) {
          <p class="mb-5 rounded-lg bg-slate-50 ring-1 ring-slate-200 px-4 py-3 text-sm text-slate-600">
            Esta nota está firmada y no puede editarse. Para agregar información use una adenda:
            queda con su propia fecha y autor.
          </p>
        }

        <div class="grid gap-5 lg:grid-cols-5">
          <!-- Mapa corporal clínico -->
          <section class="tarjeta tarjeta-cuerpo lg:col-span-2">
            <h2 class="font-semibold mb-1">Mapa corporal</h2>
            <p class="text-sm text-slate-500 mb-4">
              {{ firmada() ? 'Zonas registradas en la sesión.' : 'Toque una zona para agregarla o quitarla.' }}
            </p>
            @if (areas().length) {
              <app-mapa-corporal [areas]="areas()" [(seleccion)]="marcadas"
                                 [modo]="firmada() ? 'lectura' : 'clinico'" [pestanas]="true" />
            } @else { <app-cargando /> }

            @if (marcadas().length && !firmada()) {
              <div class="mt-4 space-y-2.5">
                @for (m of marcadas(); track m.codigo) {
                  <div class="rounded-lg ring-1 ring-slate-200 p-3">
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium">{{ m.nombre }}</span>
                      <button type="button" class="text-slate-400 hover:text-rose-600 text-lg leading-none"
                              (click)="quitarArea(m.codigo)">&times;</button>
                    </div>
                    <input type="range" min="0" max="10" step="1" class="w-full mt-2 accent-marca-600"
                           [value]="m.nivel_dolor ?? 0"
                           (input)="setNivel(m.codigo, +$any($event.target).value)">
                    <div class="flex items-center justify-between gap-2 mt-1.5">
                      <select class="campo py-1 text-xs w-36" [value]="m.movilidad ?? ''"
                              (change)="setMovilidad(m.codigo, $any($event.target).value)">
                        <option value="">Movilidad…</option>
                        <option value="normal">Normal</option>
                        <option value="limitada">Limitada</option>
                        <option value="muy_limitada">Muy limitada</option>
                      </select>
                      <label class="flex items-center gap-1.5 text-xs text-slate-600">
                        <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                               [checked]="m.inflamacion ?? false"
                               (change)="setInflamacion(m.codigo, $any($event.target).checked)">
                        Inflamación
                      </label>
                      <span class="text-xs font-semibold tabular-nums">{{ m.nivel_dolor }}/10</span>
                    </div>
                  </div>
                }
              </div>
            }
          </section>

          <!-- Nota SOAP -->
          <section class="lg:col-span-3 space-y-5">
            <div class="tarjeta tarjeta-cuerpo">
              <h2 class="font-semibold mb-4">Nota SOAP</h2>
              <div class="space-y-4">
                @for (c of camposSoap; track c.campo) {
                  <div>
                    <label class="etiqueta" [attr.for]="c.campo">
                      {{ c.etiqueta }}
                      <span class="font-normal text-slate-400 text-xs">— {{ c.ayuda }}</span>
                    </label>
                    <textarea [id]="c.campo" class="campo" [rows]="c.filas" [disabled]="firmada()"
                              (input)="setCampo(c.campo, $any($event.target).value)"
                    >{{ nota()[c.campo] ?? '' }}</textarea>
                  </div>
                }
              </div>
            </div>

            <div class="tarjeta tarjeta-cuerpo">
              <h2 class="font-semibold mb-4">Dolor</h2>
              <div class="grid gap-5 sm:grid-cols-2">
                <app-escala-dolor [(valor)]="dolorInicial" titulo="Al iniciar" />
                <app-escala-dolor [(valor)]="dolorFinal" titulo="Al terminar" />
              </div>
              @if (delta() !== 0) {
                <p class="mt-3 text-sm" [class]="delta() > 0 ? 'text-emerald-700' : 'text-rose-700'">
                  {{ delta() > 0 ? 'Mejoró ' + delta() + ' puntos en esta sesión.'
                                 : 'Empeoró ' + (-delta()) + ' puntos en esta sesión.' }}
                </p>
              }
            </div>

            <div class="tarjeta">
              <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
                <h2 class="font-semibold">Tratamientos aplicados</h2>
                @if (!firmada()) {
                  <button type="button" class="btn-secundario btn-sm" (click)="dlgTrat.set(true)">Agregar</button>
                }
              </header>
              @if (!sesion()!.tratamientos.length) {
                <app-vacio titulo="Sin tratamientos registrados" />
              } @else {
                <table class="tabla">
                  <thead><tr><th>Tratamiento</th><th class="text-right">Cant.</th>
                    <th class="text-right">Precio</th><th></th></tr></thead>
                  <tbody>
                    @for (t of sesion()!.tratamientos; track t.id) {
                      <tr>
                        <td>
                          <p class="text-sm font-medium">{{ t.nombre }}</p>
                          @if (t.notas) { <p class="text-xs text-slate-500">{{ t.notas }}</p> }
                        </td>
                        <td class="text-right tabular-nums">{{ t.cantidad }}</td>
                        <td class="text-right tabular-nums">{{ dinero(t.precio * t.cantidad) }}</td>
                        <td class="text-right">
                          @if (!firmada()) {
                            <button type="button" class="text-slate-400 hover:text-rose-600"
                                    (click)="quitarTratamiento(t.id)">&times;</button>
                          }
                        </td>
                      </tr>
                    }
                    <tr class="bg-slate-50">
                      <td colspan="2" class="font-medium">Total</td>
                      <td class="text-right font-semibold tabular-nums">
                        {{ dinero(sesion()!.total_tratamientos) }}</td>
                      <td></td>
                    </tr>
                  </tbody>
                </table>
              }
            </div>

            <div class="tarjeta tarjeta-cuerpo">
              <h2 class="font-semibold mb-4">Seguimiento</h2>
              <label class="flex items-center gap-2.5 text-sm cursor-pointer">
                <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                       [disabled]="firmada()" [checked]="requiereSeguimiento()"
                       (change)="requiereSeguimiento.set($any($event.target).checked)">
                Requiere sesión de seguimiento
              </label>
              @if (requiereSeguimiento()) {
                <div class="mt-3">
                  <label class="etiqueta" for="prox">Fecha sugerida</label>
                  <input id="prox" class="campo max-w-xs" type="date" [disabled]="firmada()"
                         [value]="proximaSugerida()"
                         (input)="proximaSugerida.set($any($event.target).value)">
                </div>
              }
            </div>

            @if (adendas().length) {
              <div class="tarjeta tarjeta-cuerpo">
                <h2 class="font-semibold mb-3">Adendas</h2>
                <ul class="space-y-3">
                  @for (a of adendas(); track a.id) {
                    <li class="border-l-2 border-slate-200 pl-3">
                      <p class="text-sm text-slate-700">{{ a.texto }}</p>
                      <p class="text-xs text-slate-400 mt-0.5">
                        {{ a.perfiles?.nombre_completo }} · {{ fechaYHora(a.creado_en) }}
                      </p>
                    </li>
                  }
                </ul>
              </div>
            }
          </section>
        </div>
      </div>

      <!-- Barra de acciones fija -->
      @if (!firmada()) {
        <div class="fixed bottom-0 inset-x-0 lg:left-60 bg-white border-t border-slate-200 px-4 py-3
                    flex items-center justify-between gap-3 no-imprimir z-20">
          <span class="text-xs text-slate-500">
            {{ guardado() ? 'Cambios guardados' : 'Hay cambios sin guardar' }}
          </span>
          <div class="flex gap-2">
            <button type="button" class="btn-secundario" [disabled]="guardando()"
                    (click)="guardar()">Guardar borrador</button>
            <button type="button" class="btn-primario" [disabled]="guardando()"
                    (click)="dlgFirmar.set(true)">Firmar y cerrar</button>
          </div>
        </div>
      }
    }

    <app-dialogo [(abierto)]="dlgTrat" titulo="Agregar tratamiento">
      <div class="space-y-4">
        <div>
          <label class="etiqueta" for="t-sel">Tratamiento</label>
          <select id="t-sel" class="campo" [value]="tratSel()"
                  (change)="tratSel.set($any($event.target).value)">
            <option value="">Seleccione…</option>
            @for (t of tratamientos(); track t.id) {
              <option [value]="t.id">{{ t.nombre }} ({{ t.duracion_min }} min)</option>
            }
          </select>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="etiqueta" for="t-cant">Cantidad</label>
            <input id="t-cant" class="campo" type="number" min="1" max="20"
                   [value]="tratCantidad()" (input)="tratCantidad.set(+$any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="t-pre">Monto cobrado (GTQ)</label>
            <input id="t-pre" class="campo" type="number" min="0" step="0.01"
                   [value]="tratPrecio()" (input)="tratPrecio.set(+$any($event.target).value)">
            <p class="ayuda">Por unidad. Total: {{ dinero(tratPrecio() * tratCantidad()) }}</p>
          </div>
        </div>
        <div>
          <label class="etiqueta" for="t-not">Notas</label>
          <input id="t-not" class="campo" [value]="tratNota()"
                 (input)="tratNota.set($any($event.target).value)">
        </div>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgTrat.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!tratSel()"
                (click)="agregarTratamiento()">Agregar</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgFirmar" titulo="Firmar la nota clínica">
      <p class="text-sm text-slate-600">
        Al firmar, la nota queda cerrada: no podrá editarse y cualquier corrección deberá
        hacerse mediante una adenda. También se encolará la invitación al paciente para
        evaluar su sesión.
      </p>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgFirmar.set(false)">Volver</button>
        <button type="button" class="btn-primario" [disabled]="guardando()" (click)="firmar()">
          {{ guardando() ? 'Firmando…' : 'Firmar' }}
        </button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgAdenda" titulo="Agregar adenda">
      <div>
        <label class="etiqueta" for="ad">Texto de la adenda</label>
        <textarea id="ad" class="campo" rows="4"
                  (input)="textoAdenda.set($any($event.target).value)">{{ textoAdenda() }}</textarea>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAdenda.set(false)">Cancelar</button>
        <button type="button" class="btn-primario"
                [disabled]="textoAdenda().trim().length < 3 || guardando()"
                (click)="guardarAdenda()">Agregar</button>
      </div>
    </app-dialogo>
  `,
})
export class EditorSesion {
  private readonly clinicaApi = inject(ClinicaService);
  private readonly catalogos = inject(CatalogosService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly id = input.required<string>();

  readonly camposSoap = [
    { campo: 'subjetivo', etiqueta: 'Subjetivo', ayuda: 'lo que refiere el paciente', filas: 3 },
    { campo: 'objetivo', etiqueta: 'Objetivo', ayuda: 'hallazgos de la exploración', filas: 3 },
    { campo: 'analisis', etiqueta: 'Análisis', ayuda: 'su valoración', filas: 2 },
    { campo: 'plan', etiqueta: 'Plan', ayuda: 'tratamiento y progresión', filas: 2 },
    { campo: 'recomendaciones', etiqueta: 'Recomendaciones', ayuda: 'ejercicios y cuidados en casa', filas: 3 },
  ];

  readonly cargando = signal(true);
  readonly guardando = signal(false);
  readonly guardado = signal(true);
  readonly sesion = signal<SesionDetalle | null>(null);
  readonly adendas = signal<any[]>([]);
  readonly tratamientos = signal<Tratamiento[]>([]);
  readonly areas = this.catalogos.areas;

  readonly nota = signal<Record<string, string | undefined>>({});
  readonly marcadas = signal<AreaMarcada[]>([]);
  readonly dolorInicial = signal(0);
  readonly dolorFinal = signal(0);
  readonly requiereSeguimiento = signal(false);
  readonly proximaSugerida = signal('');

  readonly dlgTrat = signal(false);
  readonly dlgFirmar = signal(false);
  readonly dlgAdenda = signal(false);
  readonly tratSel = signal('');
  readonly tratCantidad = signal(1);
  readonly tratPrecio = signal(0);
  readonly tratNota = signal('');
  readonly textoAdenda = signal('');

  readonly fechaYHora = fechaHora;
  readonly fecha = fechaCorta;
  readonly hora = horaCorta;
  readonly dinero = moneda;

  readonly firmada = computed(() => !!this.sesion()?.firmada_en);
  readonly delta = computed(() => this.dolorInicial() - this.dolorFinal());

  constructor() {
    void this.catalogos.cargarAreas();
    void this.catalogos.tratamientos().then((t) => this.tratamientos.set(t));
    queueMicrotask(() => void this.cargar());
  }

  private async cargar() {
    this.cargando.set(true);
    try {
      const s = await this.clinicaApi.sesion(this.id());
      this.sesion.set(s);
      if (!s) return;
      this.nota.set({
        subjetivo: s.subjetivo ?? '', objetivo: s.objetivo ?? '',
        analisis: s.analisis ?? '', plan: s.plan ?? '',
        recomendaciones: s.recomendaciones ?? '',
      });
      this.marcadas.set((s.areas ?? []).map((a) => ({ ...a, nivel_dolor: a.nivel_dolor ?? 0 })));
      this.dolorInicial.set(s.dolor_inicial ?? 0);
      this.dolorFinal.set(s.dolor_final ?? 0);
      this.requiereSeguimiento.set(s.requiere_seguimiento);
      this.proximaSugerida.set(s.proxima_sugerida ?? '');
      this.adendas.set(await this.clinicaApi.adendas(s.id).catch(() => []));
      this.guardado.set(true);
    } catch (e) {
      this.avisos.error('No se pudo abrir la sesión.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  setCampo(campo: string, valor: string) {
    this.nota.update((n) => ({ ...n, [campo]: valor }));
    this.guardado.set(false);
  }

  quitarArea(codigo: string) {
    this.marcadas.update((l) => l.filter((m) => m.codigo !== codigo));
    this.guardado.set(false);
  }

  setNivel(codigo: string, n: number) {
    this.marcadas.update((l) => l.map((m) => (m.codigo === codigo ? { ...m, nivel_dolor: n } : m)));
    this.guardado.set(false);
  }

  setMovilidad(codigo: string, v: string) {
    this.marcadas.update((l) => l.map((m) =>
      m.codigo === codigo ? { ...m, movilidad: (v || null) as AreaMarcada['movilidad'] } : m));
    this.guardado.set(false);
  }

  setInflamacion(codigo: string, v: boolean) {
    this.marcadas.update((l) => l.map((m) => (m.codigo === codigo ? { ...m, inflamacion: v } : m)));
    this.guardado.set(false);
  }

  async guardar(silencioso = false) {
    const s = this.sesion();
    if (!s || this.firmada()) return;
    this.guardando.set(true);
    try {
      const n = this.nota();
      await this.clinicaApi.guardarSesion(s.id, {
        subjetivo: n['subjetivo'] || null,
        objetivo: n['objetivo'] || null,
        analisis: n['analisis'] || null,
        plan: n['plan'] || null,
        recomendaciones: n['recomendaciones'] || null,
        dolor_inicial: this.dolorInicial(),
        dolor_final: this.dolorFinal(),
        requiere_seguimiento: this.requiereSeguimiento(),
        proxima_sugerida: this.proximaSugerida() || null,
      });

      // El mapa corporal se reemplaza completo con lo que quedó marcado.
      await this.clinicaApi.guardarAreasSesion(
        s.id, this.marcadas(), await this.catalogos.idsDeAreas(),
      );

      this.guardado.set(true);
      if (!silencioso) this.avisos.exito('Borrador guardado.');
    } catch (e) {
      this.avisos.error('No se pudo guardar la nota.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  async agregarTratamiento() {
    const s = this.sesion();
    if (!s || !this.tratSel()) return;
    try {
      await this.clinicaApi.agregarTratamiento(
        s.id, this.tratSel(), this.tratCantidad(), this.tratPrecio(),
        this.tratNota() || undefined,
      );
      this.dlgTrat.set(false);
      this.tratSel.set(''); this.tratCantidad.set(1);
      this.tratPrecio.set(0); this.tratNota.set('');
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo agregar el tratamiento.');
    }
  }

  async quitarTratamiento(id: string) {
    try {
      await this.clinicaApi.quitarTratamiento(id);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo quitar el tratamiento.');
    }
  }

  async firmar() {
    const s = this.sesion();
    if (!s) return;
    this.guardando.set(true);
    try {
      await this.guardar(true);
      const r = await this.clinicaApi.firmar(s.id);
      if (!r.ok) {
        this.avisos.error(r.error === 'ya_firmada' ? 'La nota ya estaba firmada.' : 'No se pudo firmar.');
        return;
      }
      this.dlgFirmar.set(false);
      this.avisos.exito('Nota firmada.');
      await this.cargar();
    } catch (e) {
      this.avisos.error('No se pudo firmar la nota.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  async guardarAdenda() {
    const s = this.sesion();
    if (!s) return;
    this.guardando.set(true);
    try {
      await this.clinicaApi.agregarAdenda(s.id, this.textoAdenda().trim(), this.auth.perfil()!.id);
      this.textoAdenda.set('');
      this.dlgAdenda.set(false);
      this.adendas.set(await this.clinicaApi.adendas(s.id));
      this.avisos.exito('Adenda agregada.');
    } catch {
      this.avisos.error('No se pudo agregar la adenda.');
    } finally {
      this.guardando.set(false);
    }
  }

  imprimir() { window.print(); }
}
