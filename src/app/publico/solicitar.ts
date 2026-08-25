import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CatalogosService } from '../core/api/catalogos.service';
import { CitasService } from '../core/api/citas.service';
import { AreaMarcada, CanalContacto, Slot } from '../core/modelos';
import {
  colorDolor, esEmailValido, etiquetaDolor, fechaLarga, formatearDpi, hoyIso,
  normalizarDpi, sumarDias, validarDpi,
} from '../core/util/formato';
import { MapaCorporal } from '../shared/mapa-corporal';
import { Cargando } from '../shared/ui';

/**
 * Formulario público de solicitud de cita.
 *
 * No crea usuario, no pide contraseña, no guarda sesión. Al terminar entrega un
 * código de referencia y nada más: el seguimiento ocurre por WhatsApp o correo.
 */
@Component({
  selector: 'app-solicitar',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, MapaCorporal, Cargando],
  template: `
    <div class="mx-auto max-w-3xl px-4 py-8 sm:py-12">

      @if (codigo(); as ref) {
        <!-- ============ Confirmación ============ -->
        <div class="tarjeta tarjeta-cuerpo text-center animar-entrada">
          <div class="mx-auto w-14 h-14 rounded-full bg-marca-100 grid place-items-center">
            <svg viewBox="0 0 24 24" class="w-7 h-7 text-marca-700" fill="none" stroke="currentColor" stroke-width="2.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7"/>
            </svg>
          </div>
          <h1 class="mt-4 text-2xl font-semibold">
            {{ duplicada() ? 'Ya teníamos su solicitud' : 'Solicitud recibida' }}
          </h1>
          <p class="mt-2 text-slate-600 max-w-md mx-auto">{{ mensajeExito() }}</p>

          <div class="mt-6 inline-flex flex-col items-center rounded-xl bg-slate-900 text-white px-8 py-5">
            <span class="text-[11px] uppercase tracking-widest text-slate-400">Código de referencia</span>
            <span class="mt-1 text-3xl font-bold tracking-wider font-mono">{{ ref }}</span>
          </div>

          <p class="mt-5 text-sm text-slate-500 max-w-md mx-auto leading-relaxed">
            Anote este código. Sirve para identificar su cita si nos escribe o nos llama.
            <strong class="text-slate-700">No es una contraseña</strong> y no da acceso a ninguna información.
          </p>

          <div class="mt-4 rounded-lg bg-amber-50 ring-1 ring-amber-200 px-4 py-3 text-sm text-amber-900 text-left max-w-md mx-auto">
            Su cita todavía <strong>no está confirmada</strong>. La clínica revisará la
            disponibilidad y le responderá por {{ canalTexto() }}.
          </div>

          <div class="mt-7 flex flex-wrap gap-3 justify-center">
            <button type="button" class="btn-secundario" (click)="copiar(ref)">Copiar código</button>
            <a routerLink="/" class="btn-primario">Volver al inicio</a>
          </div>
        </div>

      } @else {
        <!-- ============ Asistente ============ -->
        <header class="mb-7">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">Solicitar una cita</h1>
          <p class="mt-1.5 text-slate-600">Sin cuenta y sin contraseña. Toma unos dos minutos.</p>
        </header>

        <ol class="flex items-center gap-1.5 mb-8" aria-label="Progreso">
          @for (p of pasosTitulos; track $index) {
            <li class="flex-1">
              <div class="h-1.5 rounded-full transition-colors"
                   [class]="$index <= paso() ? 'bg-marca-600' : 'bg-slate-200'"></div>
              <span class="mt-1.5 block text-[11px] sm:text-xs"
                    [class]="$index <= paso() ? 'text-marca-700 font-medium' : 'text-slate-400'">
                {{ p }}
              </span>
            </li>
          }
        </ol>

        <div class="tarjeta tarjeta-cuerpo">

          <!-- ---------- Paso 1: identificación ---------- -->
          @if (paso() === 0) {
            <div class="space-y-5 animar-entrada">
              <div>
                <label class="etiqueta" for="dpi">DPI <span class="text-rose-600">*</span></label>
                <input id="dpi" class="campo font-mono tracking-wider"
                       [class.campo-error]="dpiTocado() && !dpiValido()"
                       inputmode="numeric" autocomplete="off" placeholder="0000 00000 0000"
                       [value]="dpi()" (input)="escribirDpi($event)" (blur)="dpiTocado.set(true)">
                @if (dpiTocado() && !dpiValido()) {
                  <p class="error-texto">{{ errorDpi() }}</p>
                } @else {
                  <p class="ayuda">13 dígitos. Lo usamos para vincular su historial; nunca se muestra completo.</p>
                }
              </div>

              <div>
                <label class="etiqueta" for="nombre">Nombre completo <span class="text-rose-600">*</span></label>
                <input id="nombre" class="campo" autocomplete="name" placeholder="Como aparece en su DPI"
                       [class.campo-error]="nombreTocado() && !nombreValido()"
                       [value]="nombre()" (input)="nombre.set(valor($event))" (blur)="nombreTocado.set(true)">
                @if (nombreTocado() && !nombreValido()) {
                  <p class="error-texto">Escriba al menos su nombre y un apellido.</p>
                }
              </div>

              <div class="grid gap-4 sm:grid-cols-2">
                <div>
                  <label class="etiqueta" for="tel">Teléfono</label>
                  <input id="tel" class="campo" inputmode="tel" autocomplete="tel" placeholder="0000-0000"
                         [value]="telefono()" (input)="escribirTelefono($event)">
                </div>
                <div>
                  <label class="etiqueta" for="wa">WhatsApp</label>
                  <input id="wa" class="campo" inputmode="tel" placeholder="0000-0000"
                         [disabled]="waIgual()"
                         [value]="waIgual() ? telefono() : whatsapp()"
                         (input)="whatsapp.set(valor($event))">
                  <label class="mt-2 flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
                    <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                           [checked]="waIgual()" (change)="waIgual.set(marcado($event))">
                    Es el mismo número
                  </label>
                </div>
              </div>

              <div>
                <label class="etiqueta" for="email">Correo electrónico</label>
                <input id="email" class="campo" type="email" inputmode="email" autocomplete="email"
                       placeholder="nombre&#64;correo.com"
                       [class.campo-error]="email() !== '' && !emailValido()"
                       [value]="email()" (input)="email.set(valor($event))">
                @if (email() !== '' && !emailValido()) {
                  <p class="error-texto">Revise el formato del correo.</p>
                }
              </div>

              <div>
                <span class="etiqueta">¿Por dónde prefiere que le respondamos? <span class="text-rose-600">*</span></span>
                <div class="grid grid-cols-2 gap-2">
                  @for (c of canales; track c.id) {
                    <button type="button"
                            class="rounded-lg px-4 py-3 text-sm ring-1 text-left transition-colors"
                            [class]="canal() === c.id
                              ? 'bg-marca-50 ring-marca-500 text-marca-900 font-medium'
                              : 'bg-white ring-slate-300 text-slate-700 hover:bg-slate-50'"
                            [disabled]="!canalPosible(c.id)"
                            [class.opacity-40]="!canalPosible(c.id)"
                            (click)="canal.set(c.id)">
                      {{ c.etiqueta }}
                      @if (!canalPosible(c.id)) {
                        <span class="block text-[11px] text-slate-400 font-normal">Falta el dato</span>
                      }
                    </button>
                  }
                </div>
              </div>

              @if (!hayContacto()) {
                <p class="rounded-lg bg-amber-50 ring-1 ring-amber-200 px-3 py-2 text-sm text-amber-900">
                  Necesitamos al menos un teléfono, WhatsApp o correo para poder responderle.
                </p>
              }
            </div>
          }

          <!-- ---------- Paso 2: fecha y horario ---------- -->
          @if (paso() === 1) {
            <div class="space-y-5 animar-entrada">
              <div>
                <label class="etiqueta" for="fecha">Fecha que prefiere <span class="text-rose-600">*</span></label>
                <input id="fecha" class="campo" type="date"
                       [min]="fechaMin" [max]="fechaMax"
                       [value]="fecha()" (change)="elegirFecha($event)">
                @if (fecha()) { <p class="ayuda first-letter:uppercase">{{ fechaBonita() }}</p> }
              </div>

              @if (fecha()) {
                <div>
                  <span class="etiqueta">Horario</span>
                  @if (cargandoSlots()) {
                    <app-cargando texto="Consultando disponibilidad…" />
                  } @else if (slotsLibres().length) {
                    <div class="grid grid-cols-3 sm:grid-cols-4 gap-2">
                      @for (s of slotsLibres(); track s.hora) {
                        <button type="button"
                                class="rounded-lg py-2.5 text-sm ring-1 transition-colors"
                                [class]="hora() === s.hora
                                  ? 'bg-marca-600 text-white ring-marca-600 font-medium'
                                  : 'bg-white ring-slate-300 hover:bg-slate-50'"
                                (click)="hora.set(s.hora)">{{ horaBonita(s.hora) }}</button>
                      }
                    </div>
                    <p class="ayuda">
                      Estos horarios están libres hoy, pero la cita se confirma hasta que la
                      clínica revise su solicitud.
                    </p>
                  } @else {
                    <div class="rounded-lg bg-slate-50 ring-1 ring-slate-200 px-4 py-3 text-sm text-slate-600">
                      No hay horarios publicados para esa fecha. Indíquenos su preferencia y
                      buscamos una opción.
                    </div>
                    <div class="mt-3 grid grid-cols-3 gap-2">
                      @for (f of franjas; track f.id) {
                        <button type="button"
                                class="rounded-lg py-2.5 text-sm ring-1 transition-colors"
                                [class]="franja() === f.id
                                  ? 'bg-marca-600 text-white ring-marca-600 font-medium'
                                  : 'bg-white ring-slate-300 hover:bg-slate-50'"
                                (click)="franja.set(f.id)">{{ f.etiqueta }}</button>
                      }
                    </div>
                  }
                </div>
              }

              <label class="flex items-start gap-2.5 text-sm text-slate-700 cursor-pointer">
                <input type="checkbox" class="mt-0.5 rounded border-slate-300 text-marca-600"
                       [checked]="primeraVez()" (change)="primeraVez.set(marcado($event))">
                Es mi primera visita a {{ nombreClinica }}
              </label>
            </div>
          }

          <!-- ---------- Paso 3: áreas de molestia ---------- -->
          @if (paso() === 2) {
            <div class="space-y-5 animar-entrada">
              <div>
                <h2 class="text-base font-semibold">¿Dónde le molesta?</h2>
                <p class="text-sm text-slate-600 mt-1">
                  Toque las zonas en la figura. Después ajuste qué tan fuerte es el dolor en cada una.
                </p>
              </div>

              @if (areas().length) {
                <app-mapa-corporal [areas]="areas()" [(seleccion)]="marcadas"
                                   modo="seleccion" [pestanas]="true" />
              } @else {
                <app-cargando texto="Cargando el mapa corporal…" />
              }

              @if (marcadas().length) {
                <div class="space-y-3 pt-2">
                  <h3 class="text-sm font-medium text-slate-700">
                    Intensidad por zona ({{ marcadas().length }})
                  </h3>
                  @for (m of marcadas(); track m.codigo) {
                    <div class="rounded-lg ring-1 ring-slate-200 p-3">
                      <div class="flex items-center justify-between gap-3">
                        <span class="text-sm font-medium">{{ m.nombre }}</span>
                        <div class="flex items-center gap-2">
                          <span class="text-xs font-semibold" [style.color]="color(m.intensidad ?? 0)">
                            {{ m.intensidad }}/10 · {{ etiqueta(m.intensidad ?? 0) }}
                          </span>
                          <button type="button" class="text-slate-400 hover:text-rose-600 text-lg leading-none"
                                  (click)="quitar(m.codigo)" [attr.aria-label]="'Quitar ' + m.nombre">&times;</button>
                        </div>
                      </div>
                      <input type="range" min="0" max="10" step="1" class="w-full mt-2 accent-marca-600"
                             [value]="m.intensidad ?? 0"
                             (input)="cambiarIntensidad(m.codigo, $event)">
                    </div>
                  }
                </div>
              } @else {
                <p class="rounded-lg bg-amber-50 ring-1 ring-amber-200 px-3 py-2 text-sm text-amber-900">
                  Marque al menos una zona para continuar.
                </p>
              }

              <div>
                <label class="etiqueta" for="motivo">Motivo de la consulta</label>
                <input id="motivo" class="campo" maxlength="180"
                       placeholder="Ej. dolor lumbar al levantar peso"
                       [value]="motivo()" (input)="motivo.set(valor($event))">
              </div>

              <div>
                <label class="etiqueta" for="coment">Comentarios adicionales</label>
                <textarea id="coment" class="campo" rows="3" maxlength="600"
                          placeholder="Lesiones previas, cirugías, desde cuándo le molesta…"
                          (input)="comentarios.set(valor($event))">{{ comentarios() }}</textarea>
              </div>
            </div>
          }

          <!-- ---------- Paso 4: revisión ---------- -->
          @if (paso() === 3) {
            <div class="space-y-5 animar-entrada">
              <h2 class="text-base font-semibold">Revise antes de enviar</h2>

              <dl class="divide-y divide-slate-100 text-sm">
                @for (r of resumen(); track r.etiqueta) {
                  <div class="py-2.5 grid grid-cols-3 gap-3">
                    <dt class="text-slate-500">{{ r.etiqueta }}</dt>
                    <dd class="col-span-2 text-slate-800">{{ r.valor }}</dd>
                  </div>
                }
              </dl>

              <label class="flex items-start gap-2.5 text-sm text-slate-700 cursor-pointer
                            rounded-lg bg-slate-50 ring-1 ring-slate-200 p-3">
                <input type="checkbox" class="mt-0.5 rounded border-slate-300 text-marca-600"
                       [checked]="aceptaPolitica()" (change)="aceptaPolitica.set(marcado($event))">
                <span>
                  Autorizo a {{ nombreClinica }} a tratar mis datos personales y de salud con el fin
                  de agendar y brindar la atención solicitada, según la
                  <a routerLink="/politica-de-datos" target="_blank"
                     class="text-marca-700 underline">política de tratamiento de datos</a>.
                </span>
              </label>

              @if (errorEnvio()) {
                <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
                  {{ errorEnvio() }}
                </p>
              }
            </div>
          }

          <!-- ---------- Navegación ---------- -->
          <div class="mt-7 pt-5 border-t border-slate-200 flex items-center justify-between gap-3">
            <button type="button" class="btn-fantasma" [disabled]="paso() === 0 || enviando()"
                    (click)="atras()">Atrás</button>

            @if (paso() < 3) {
              <button type="button" class="btn-primario" [disabled]="!pasoValido()"
                      (click)="adelante()">Continuar</button>
            } @else {
              <button type="button" class="btn-primario min-w-40"
                      [disabled]="!aceptaPolitica() || enviando()" (click)="enviar()">
                {{ enviando() ? 'Enviando…' : 'Enviar solicitud' }}
              </button>
            }
          </div>
        </div>

        <p class="mt-5 text-center text-xs text-slate-400">
          No creamos ninguna cuenta a su nombre. Este formulario es el único paso.
        </p>
      }
    </div>
  `,
})
export class Solicitar {
  private readonly catalogos = inject(CatalogosService);
  private readonly citas = inject(CitasService);

  readonly nombreClinica = 'NeoTerapia';
  readonly pasosTitulos = ['Sus datos', 'Fecha', 'Molestias', 'Revisión'];
  readonly canales: Array<{ id: CanalContacto; etiqueta: string }> = [
    { id: 'whatsapp', etiqueta: 'WhatsApp' },
    { id: 'email', etiqueta: 'Correo electrónico' },
  ];
  readonly franjas = [
    { id: 'manana' as const, etiqueta: 'Mañana' },
    { id: 'tarde' as const, etiqueta: 'Tarde' },
    { id: 'indistinto' as const, etiqueta: 'Cualquiera' },
  ];

  readonly fechaMin = hoyIso();
  readonly fechaMax = sumarDias(hoyIso(), 60);

  readonly paso = signal(0);

  // Paso 1
  readonly dpi = signal('');
  readonly dpiTocado = signal(false);
  readonly nombre = signal('');
  readonly nombreTocado = signal(false);
  readonly telefono = signal('');
  readonly whatsapp = signal('');
  readonly waIgual = signal(true);
  readonly email = signal('');
  readonly canal = signal<CanalContacto>('whatsapp');

  // Paso 2
  readonly fecha = signal('');
  readonly hora = signal<string | null>(null);
  readonly franja = signal<'manana' | 'tarde' | 'indistinto'>('indistinto');
  readonly primeraVez = signal(false);
  readonly slots = signal<Slot[]>([]);
  readonly cargandoSlots = signal(false);

  // Paso 3
  readonly areas = this.catalogos.areas;
  readonly marcadas = signal<AreaMarcada[]>([]);
  readonly motivo = signal('');
  readonly comentarios = signal('');

  // Paso 4
  readonly aceptaPolitica = signal(false);
  readonly enviando = signal(false);
  readonly errorEnvio = signal('');
  readonly codigo = signal<string | null>(null);
  readonly duplicada = signal(false);
  readonly mensajeExito = signal('');

  readonly color = colorDolor;
  readonly etiqueta = etiquetaDolor;

  constructor() {
    void this.catalogos.cargarAreas();
  }

  // --- Helpers de plantilla ---------------------------------------------
  valor(e: Event): string { return (e.target as HTMLInputElement).value; }
  marcado(e: Event): boolean { return (e.target as HTMLInputElement).checked; }

  escribirDpi(e: Event) {
    const bruto = (e.target as HTMLInputElement).value;
    this.dpi.set(formatearDpi(bruto));
  }

  escribirTelefono(e: Event) {
    const v = this.valor(e);
    this.telefono.set(v);
    if (this.waIgual()) this.whatsapp.set(v);
  }

  // --- Validaciones -------------------------------------------------------
  readonly resultadoDpi = computed(() => validarDpi(this.dpi()));
  readonly dpiValido = computed(() => this.resultadoDpi().valido);
  readonly errorDpi = computed(() => this.resultadoDpi().mensaje ?? 'DPI inválido.');
  readonly nombreValido = computed(() => {
    const n = this.nombre().trim();
    return n.length >= 5 && n.split(/\s+/).length >= 2;
  });
  readonly emailValido = computed(() => esEmailValido(this.email()));
  readonly telefonoEfectivo = computed(() => (this.waIgual() ? this.telefono() : this.whatsapp()));
  readonly hayContacto = computed(
    () => !!(this.telefono().trim() || this.telefonoEfectivo().trim() || (this.email().trim() && this.emailValido())),
  );

  canalPosible(c: CanalContacto): boolean {
    if (c === 'email') return this.emailValido();
    return !!(this.telefono().trim() || this.telefonoEfectivo().trim());
  }

  readonly slotsLibres = computed(() => this.slots().filter((s) => s.disponible));

  readonly pasoValido = computed(() => {
    switch (this.paso()) {
      case 0:
        return this.dpiValido() && this.nombreValido() && this.hayContacto()
          && this.canalPosible(this.canal())
          && (this.email() === '' || this.emailValido());
      case 1:
        return !!this.fecha() && (!!this.hora() || this.slotsLibres().length === 0);
      case 2:
        return this.marcadas().length > 0;
      default:
        return true;
    }
  });

  readonly fechaBonita = computed(() =>
    this.fecha() ? fechaLarga(`${this.fecha()}T12:00:00`) : '');

  canalTexto = computed(() => (this.canal() === 'email' ? 'correo electrónico' : 'WhatsApp'));

  horaBonita(hhmm: string): string {
    const [h, m] = hhmm.split(':').map(Number);
    const suf = h >= 12 ? 'p.m.' : 'a.m.';
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12}:${String(m).padStart(2, '0')} ${suf}`;
  }

  readonly resumen = computed(() => {
    const filas = [
      { etiqueta: 'DPI', valor: this.dpi() },
      { etiqueta: 'Nombre', valor: this.nombre() },
      { etiqueta: 'Contacto', valor: [this.telefono(), this.email()].filter(Boolean).join(' · ') || '—' },
      { etiqueta: 'Respondemos por', valor: this.canal() === 'email' ? 'Correo electrónico' : 'WhatsApp' },
      { etiqueta: 'Fecha', valor: this.fechaBonita() },
      {
        etiqueta: 'Horario',
        valor: this.hora()
          ? this.horaBonita(this.hora()!)
          : this.franjas.find((f) => f.id === this.franja())!.etiqueta,
      },
      {
        etiqueta: 'Zonas',
        valor: this.marcadas().map((m) => `${m.nombre} (${m.intensidad}/10)`).join(', '),
      },
    ];
    if (this.motivo().trim()) filas.push({ etiqueta: 'Motivo', valor: this.motivo() });
    if (this.comentarios().trim()) filas.push({ etiqueta: 'Comentarios', valor: this.comentarios() });
    return filas;
  });

  // --- Navegación ---------------------------------------------------------
  adelante() {
    if (!this.pasoValido()) return;
    this.paso.update((p) => Math.min(p + 1, 3));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  atras() {
    this.paso.update((p) => Math.max(p - 1, 0));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async elegirFecha(e: Event) {
    const f = this.valor(e);
    this.fecha.set(f);
    this.hora.set(null);
    this.slots.set([]);
    if (!f) return;
    this.cargandoSlots.set(true);
    try {
      this.slots.set(await this.catalogos.slots(f));
    } catch {
      this.slots.set([]);
    } finally {
      this.cargandoSlots.set(false);
    }
  }

  // --- Áreas --------------------------------------------------------------
  quitar(codigo: string) {
    this.marcadas.update((l) => l.filter((m) => m.codigo !== codigo));
  }

  cambiarIntensidad(codigo: string, e: Event) {
    const n = Number((e.target as HTMLInputElement).value);
    this.marcadas.update((l) => l.map((m) => (m.codigo === codigo ? { ...m, intensidad: n } : m)));
  }

  // --- Envío --------------------------------------------------------------
  async enviar() {
    if (!this.aceptaPolitica() || this.enviando()) return;
    this.enviando.set(true);
    this.errorEnvio.set('');

    try {
      const r = await this.citas.solicitar({
        dpi: normalizarDpi(this.dpi()),
        tipo_documento: 'dpi',
        nombre_completo: this.nombre().trim(),
        telefono: this.telefono().trim() || null,
        whatsapp: this.telefonoEfectivo().trim() || null,
        email: this.emailValido() ? this.email().trim() : null,
        canal_preferido: this.canal(),
        fecha: this.fecha(),
        hora: this.hora(),
        franja: this.hora() ? 'indistinto' : this.franja(),
        motivo_consulta: this.motivo().trim() || null,
        comentarios: this.comentarios().trim() || null,
        es_primera_vez: this.primeraVez(),
        acepta_politica: true,
        areas: this.marcadas().map((m) => ({
          codigo: m.codigo,
          intensidad: m.intensidad ?? 0,
        })),
      });

      if (!r.ok) {
        this.errorEnvio.set(r.mensaje ?? 'No se pudo enviar la solicitud. Intente de nuevo.');
        // Si el problema es de un paso anterior, se devuelve al usuario ahí.
        if (r.error === 'dpi_invalido' || r.error === 'nombre_invalido' || r.error === 'sin_contacto') {
          this.paso.set(0);
        } else if (r.error?.startsWith('fecha') || r.error === 'horario_muy_proximo') {
          this.paso.set(1);
        } else if (r.error === 'sin_areas') {
          this.paso.set(2);
        }
        return;
      }

      this.duplicada.set(!!r.duplicada);
      this.mensajeExito.set(r.mensaje ?? 'Su solicitud fue recibida.');
      this.codigo.set(r.codigo_referencia ?? null);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (e) {
      this.errorEnvio.set(
        'No pudimos comunicarnos con el servidor. Revise su conexión e intente de nuevo.',
      );
      console.error(e);
    } finally {
      this.enviando.set(false);
    }
  }

  async copiar(texto: string) {
    try {
      await navigator.clipboard.writeText(texto);
    } catch {
      /* el usuario siempre puede copiarlo a mano */
    }
  }
}
