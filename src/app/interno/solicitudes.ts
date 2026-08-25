import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { CitasService } from '../core/api/citas.service';
import { AreaMarcada, CitaListado, EstadoCita, Perfil, Slot } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import {
  colorDolor, fechaCorta, fechaLarga, formatearTelefono, haceCuanto, hoyIso, horaCorta,
} from '../core/util/formato';
import { MapaCorporal } from '../shared/mapa-corporal';
import { Cargando, ChipEstado, Dialogo, Vacio } from '../shared/ui';

type Pestana = 'pendientes' | 'confirmadas' | 'historial';

@Component({
  selector: 'app-solicitudes',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ChipEstado, Dialogo, Cargando, Vacio, MapaCorporal],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Solicitudes de cita</h1>
          <p class="text-sm text-slate-500 mt-0.5">
            Entran del formulario público. Confirmar genera los enlaces para el paciente.
          </p>
        </div>
        <input class="campo max-w-xs" placeholder="Buscar por código o nombre…"
               [value]="busqueda()" (input)="buscar($event)">
      </header>

      <div class="flex gap-1 p-1 bg-slate-100 rounded-lg w-fit mb-5">
        @for (p of pestanas; track p.id) {
          <button type="button" class="px-4 py-1.5 text-sm rounded-md transition-colors"
                  [class]="pestana() === p.id ? 'bg-white shadow-sm font-medium' : 'text-slate-500'"
                  (click)="cambiarPestana(p.id)">{{ p.etiqueta }}</button>
        }
      </div>

      @if (cargando()) {
        <app-cargando />
      } @else if (lista().length === 0) {
        <div class="tarjeta">
          <app-vacio titulo="No hay solicitudes en esta vista"
                     detalle="Las solicitudes nuevas del sitio público aparecerán aquí." />
        </div>
      } @else {
        <div class="space-y-3">
          @for (c of lista(); track c.id) {
            <article class="tarjeta p-4 sm:p-5">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex items-center gap-2.5 flex-wrap">
                    <a [routerLink]="['/panel/pacientes', c.paciente_id]"
                       class="font-semibold hover:text-marca-700">{{ c.nombre_completo }}</a>
                    <app-chip-estado [estado]="c.estado" />
                    @if (c.es_primera_vez) { <span class="chip-neutro">1.ª visita</span> }
                    @if (c.alertas_pendientes > 0) {
                      <span class="chip bg-amber-50 text-amber-800 ring-amber-200">
                        ⚠ {{ c.alertas_pendientes }}
                      </span>
                    }
                  </div>
                  <p class="mt-1 text-sm text-slate-500 flex flex-wrap gap-x-3 gap-y-0.5">
                    <span class="dpi">{{ c.dpi_mascara }}</span>
                    <span class="font-mono text-xs">{{ c.codigo_referencia }}</span>
                    @if (c.telefono_declarado) { <span>{{ tel(c.telefono_declarado) }}</span> }
                    @if (c.email_declarado) { <span class="truncate">{{ c.email_declarado }}</span> }
                  </p>
                </div>

                <div class="text-right shrink-0">
                  @if (c.inicio_programado) {
                    <p class="text-sm font-medium first-letter:uppercase">{{ fLarga(c.inicio_programado) }}</p>
                    <p class="text-sm text-slate-500">{{ hora(c.inicio_programado) }}</p>
                  } @else {
                    <p class="text-sm font-medium">{{ fCorta(c.fecha_solicitada + 'T12:00:00') }}</p>
                    <p class="text-sm text-slate-500">
                      {{ c.hora_solicitada ? c.hora_solicitada.slice(0,5) : etiquetaFranja(c.franja_solicitada) }}
                    </p>
                  }
                  <p class="text-xs text-slate-400 mt-0.5">{{ cuando(c.creado_en) }}</p>
                </div>
              </div>

              @if (c.motivo_consulta || c.comentarios_paciente) {
                <p class="mt-3 text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2">
                  @if (c.motivo_consulta) { <span class="font-medium">{{ c.motivo_consulta }}</span> }
                  @if (c.comentarios_paciente) {
                    <span class="block text-slate-600 mt-0.5">{{ c.comentarios_paciente }}</span>
                  }
                </p>
              }

              @if (c.areas.length) {
                <div class="mt-3 flex flex-wrap gap-1.5">
                  @for (a of c.areas; track a.codigo) {
                    <span class="chip ring-slate-200 bg-white">
                      <span class="w-2 h-2 rounded-full" [style.background]="color(a.intensidad ?? 0)"></span>
                      {{ a.nombre }} <span class="text-slate-400">{{ a.intensidad }}/10</span>
                    </span>
                  }
                </div>
              }

              <div class="mt-4 pt-3 border-t border-slate-100 flex flex-wrap gap-2">
                @if (c.estado === 'solicitada') {
                  <button type="button" class="btn-primario btn-sm" (click)="abrirConfirmar(c)">Confirmar</button>
                  <button type="button" class="btn-secundario btn-sm" (click)="abrirRechazo(c)">Rechazar</button>
                }
                @if (c.estado === 'confirmada') {
                  <button type="button" class="btn-secundario btn-sm" (click)="abrirReprogramar(c)">Reprogramar</button>
                  <button type="button" class="btn-secundario btn-sm" (click)="abrirCancelar(c)">Cancelar</button>
                  <button type="button" class="btn-secundario btn-sm" (click)="copiarEnlaces(c)">Copiar enlaces</button>
                  <button type="button" class="btn-fantasma btn-sm" (click)="asistencia(c, true)">Marcar atendida</button>
                  <button type="button" class="btn-fantasma btn-sm" (click)="asistencia(c, false)">No asistió</button>
                }
                <button type="button" class="btn-fantasma btn-sm ml-auto" (click)="verDetalle(c)">Detalle</button>
              </div>
            </article>
          }
        </div>
      }
    </div>

    <!-- ============ Confirmar / reprogramar ============ -->
    <app-dialogo [(abierto)]="dlgAgenda" [titulo]="modo() === 'confirmar' ? 'Confirmar cita' : 'Reprogramar cita'"
                 [subtitulo]="seleccion()?.nombre_completo ?? ''" ancho="lg">
      @if (seleccion(); as c) {
        <div class="space-y-4">
          @if (modo() === 'confirmar' && c.hora_solicitada) {
            <p class="rounded-lg bg-slate-50 ring-1 ring-slate-200 px-3 py-2 text-sm">
              El paciente pidió el <strong>{{ fCorta(c.fecha_solicitada + 'T12:00:00') }}</strong>
              a las <strong>{{ c.hora_solicitada.slice(0,5) }}</strong>.
            </p>
          }

          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label class="etiqueta" for="fa">Fecha</label>
              <input id="fa" class="campo" type="date" [min]="hoy"
                     [value]="fechaSel()" (change)="cambiarFecha($event)">
            </div>
            <div>
              <label class="etiqueta" for="pa">Fisioterapeuta</label>
              <select id="pa" class="campo" [value]="fisioSel()"
                      (change)="cambiarFisio($event)">
                <option value="">Sin asignar (se define después)</option>
                @for (f of fisios(); track f.id) {
                  <option [value]="f.id">{{ f.nombre_completo }}</option>
                }
              </select>
            </div>
          </div>

          <div>
            <span class="etiqueta">Hora</span>
            @if (cargandoSlots()) {
              <app-cargando texto="Consultando agenda…" />
            } @else if (slots().length) {
              <div class="grid grid-cols-4 sm:grid-cols-6 gap-1.5">
                @for (s of slots(); track s.hora) {
                  <button type="button"
                          class="rounded-lg py-2 text-xs ring-1 transition-colors tabular-nums"
                          [class]="horaSel() === s.hora
                            ? 'bg-marca-600 text-white ring-marca-600 font-medium'
                            : s.disponible
                              ? 'bg-white ring-slate-300 hover:bg-slate-50'
                              : 'bg-slate-100 ring-slate-200 text-slate-400 line-through'"
                          [disabled]="!s.disponible && horaSel() !== s.hora"
                          (click)="horaSel.set(s.hora)">{{ s.hora.slice(0,5) }}</button>
                }
              </div>
            } @else {
              <p class="text-sm text-slate-500">No hay horario configurado para ese día.</p>
            }
            <div class="mt-2 flex items-center gap-2">
              <label class="text-xs text-slate-500" for="hm">o escriba una hora:</label>
              <input id="hm" class="campo w-32 py-1.5 text-sm" type="time"
                     [value]="horaSel()?.slice(0,5) ?? ''"
                     (change)="horaSel.set($any($event.target).value + ':00')">
            </div>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label class="etiqueta" for="dur">Duración (min)</label>
              <input id="dur" class="campo" type="number" min="10" max="240" step="5"
                     [value]="duracion()" (input)="duracion.set(+$any($event.target).value)">
            </div>
            <div>
              <label class="etiqueta" for="cons">Consultorio</label>
              <input id="cons" class="campo" [value]="consultorio()"
                     (input)="consultorio.set($any($event.target).value)">
            </div>
          </div>

          <div>
            <label class="etiqueta" for="nota">
              {{ modo() === 'confirmar' ? 'Nota interna (opcional)' : 'Motivo de la reprogramación' }}
            </label>
            <textarea id="nota" class="campo" rows="2"
                      (input)="nota.set($any($event.target).value)">{{ nota() }}</textarea>
          </div>

          @if (errorDlg()) {
            <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
              {{ errorDlg() }}
            </p>
          }
        </div>
      }

      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAgenda.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!puedeAgendar() || guardando()"
                (click)="guardarAgenda()">
          {{ guardando() ? 'Guardando…' : (modo() === 'confirmar' ? 'Confirmar cita' : 'Reprogramar') }}
        </button>
      </div>
    </app-dialogo>

    <!-- ============ Rechazar / cancelar ============ -->
    <app-dialogo [(abierto)]="dlgMotivo"
                 [titulo]="modo() === 'rechazar' ? 'Rechazar solicitud' : 'Cancelar cita'"
                 [subtitulo]="seleccion()?.nombre_completo ?? ''">
      <div class="space-y-3">
        <p class="text-sm text-slate-600">
          Se le avisará al paciente por su canal preferido. El motivo se incluye en el mensaje.
        </p>
        <div>
          <label class="etiqueta" for="mot">Motivo</label>
          <textarea id="mot" class="campo" rows="3" [class.campo-error]="motivoCorto()"
                    (input)="nota.set($any($event.target).value)">{{ nota() }}</textarea>
          @if (motivoCorto()) { <p class="error-texto">Escriba un motivo de al menos 3 caracteres.</p> }
        </div>
        <div class="flex flex-wrap gap-1.5">
          @for (m of motivosRapidos; track m) {
            <button type="button" class="chip-neutro hover:bg-slate-200" (click)="nota.set(m)">{{ m }}</button>
          }
        </div>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgMotivo.set(false)">Volver</button>
        <button type="button" class="btn-peligro" [disabled]="motivoCorto() || guardando()"
                (click)="guardarMotivo()">
          {{ guardando() ? 'Guardando…' : 'Confirmar' }}
        </button>
      </div>
    </app-dialogo>

    <!-- ============ Detalle ============ -->
    <app-dialogo [(abierto)]="dlgDetalle" titulo="Detalle de la solicitud"
                 [subtitulo]="seleccion()?.codigo_referencia ?? ''" ancho="xl">
      @if (seleccion(); as c) {
        <div class="grid gap-6 sm:grid-cols-2">
          <div>
            <dl class="divide-y divide-slate-100 text-sm">
              @for (f of detalle(); track f.k) {
                <div class="py-2 grid grid-cols-3 gap-2">
                  <dt class="text-slate-500">{{ f.k }}</dt>
                  <dd class="col-span-2 text-slate-800 break-words">{{ f.v }}</dd>
                </div>
              }
            </dl>

            @if (enlaces(); as e) {
              <div class="mt-4 space-y-2">
                <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">
                  Enlaces para el paciente
                </p>
                @for (k of ['confirmar','cancelar']; track k) {
                  <div class="flex items-center gap-2">
                    <input class="campo text-xs py-1.5 font-mono" readonly [value]="e[k]">
                    <button type="button" class="btn-secundario btn-sm shrink-0"
                            (click)="copiar(e[k])">Copiar</button>
                  </div>
                }
                <p class="text-xs text-slate-400">
                  Aún no hay proveedor de correo/WhatsApp conectado: péguelos manualmente.
                </p>
              </div>
            }
          </div>

          <div>
            @if (c.areas.length) {
              <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold mb-2">
                Áreas declaradas
              </p>
              <app-mapa-corporal [areas]="areasCatalogo()" [seleccion]="areasDeCita()"
                                 modo="lectura" [leyenda]="false" />
            }
          </div>
        </div>
      }
      <div acciones class="flex justify-between gap-2">
        <a [routerLink]="['/panel/pacientes', seleccion()?.paciente_id]"
           class="btn-secundario" (click)="dlgDetalle.set(false)">Abrir ficha</a>
        <button type="button" class="btn-primario" (click)="dlgDetalle.set(false)">Cerrar</button>
      </div>
    </app-dialogo>
  `,
})
export class Solicitudes {
  private readonly citas = inject(CitasService);
  private readonly catalogos = inject(CatalogosService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly pestanas: Array<{ id: Pestana; etiqueta: string }> = [
    { id: 'pendientes', etiqueta: 'Por atender' },
    { id: 'confirmadas', etiqueta: 'Confirmadas' },
    { id: 'historial', etiqueta: 'Historial' },
  ];
  readonly motivosRapidos = [
    'Sin disponibilidad en la fecha solicitada',
    'El paciente solicitó la cancelación',
    'Fuera del área de atención de la clínica',
    'No se pudo contactar al paciente',
  ];

  readonly hoy = hoyIso();
  readonly cargando = signal(true);
  readonly pestana = signal<Pestana>('pendientes');
  readonly busqueda = signal('');
  readonly lista = signal<CitaListado[]>([]);
  readonly fisios = signal<Perfil[]>([]);
  readonly areasCatalogo = this.catalogos.areas;

  readonly seleccion = signal<CitaListado | null>(null);
  readonly modo = signal<'confirmar' | 'reprogramar' | 'rechazar' | 'cancelar'>('confirmar');
  readonly dlgAgenda = signal(false);
  readonly dlgMotivo = signal(false);
  readonly dlgDetalle = signal(false);
  readonly guardando = signal(false);
  readonly errorDlg = signal('');
  readonly enlaces = signal<Record<string, string> | null>(null);

  readonly fechaSel = signal('');
  readonly horaSel = signal<string | null>(null);
  readonly fisioSel = signal('');
  readonly duracion = signal(45);
  readonly consultorio = signal('');
  readonly nota = signal('');
  readonly slots = signal<Slot[]>([]);
  readonly cargandoSlots = signal(false);

  readonly color = colorDolor;
  readonly hora = horaCorta;
  readonly fCorta = fechaCorta;
  readonly fLarga = fechaLarga;
  readonly cuando = haceCuanto;
  readonly tel = formatearTelefono;

  private temporizador?: ReturnType<typeof setTimeout>;

  readonly motivoCorto = computed(() => this.nota().trim().length < 3);
  // El fisioterapeuta NO es obligatorio: se puede confirmar la hora y asignar
  // a quien atienda más adelante, desde la agenda.
  readonly puedeAgendar = computed(() => !!this.fechaSel() && !!this.horaSel());

  readonly areasDeCita = computed<AreaMarcada[]>(
    () => (this.seleccion()?.areas ?? []).map((a) => ({ ...a, nivel_dolor: a.intensidad ?? 0 })),
  );

  readonly detalle = computed(() => {
    const c = this.seleccion();
    if (!c) return [];
    const filas: Array<{ k: string; v: string }> = [
      { k: 'Código', v: c.codigo_referencia },
      { k: 'Paciente', v: c.nombre_completo },
      { k: 'Nombre declarado', v: c.nombre_declarado },
      { k: 'Documento', v: c.dpi_mascara },
      { k: 'Teléfono', v: formatearTelefono(c.telefono_declarado) || '—' },
      { k: 'WhatsApp', v: formatearTelefono(c.whatsapp_declarado) || '—' },
      { k: 'Correo', v: c.email_declarado ?? '—' },
      { k: 'Canal preferido', v: c.canal_preferido },
      { k: 'Origen', v: c.origen },
      { k: 'Solicitó', v: `${fechaCorta(c.fecha_solicitada + 'T12:00:00')} ${c.hora_solicitada?.slice(0, 5) ?? ''}` },
      { k: 'Recibida', v: `${fechaCorta(c.creado_en)} · ${horaCorta(c.creado_en)}` },
    ];
    if (c.inicio_programado) {
      filas.push({ k: 'Agendada', v: `${fechaCorta(c.inicio_programado)} · ${horaCorta(c.inicio_programado)}` });
      filas.push({ k: 'Fisioterapeuta', v: c.fisioterapeuta ?? '—' });
    }
    if (c.motivo_estado) filas.push({ k: 'Motivo del estado', v: c.motivo_estado });
    return filas;
  });

  constructor() {
    void this.catalogos.cargarAreas();
    void this.catalogos.fisioterapeutas().then((f) => this.fisios.set(f));
    void this.cargar();
  }

  private estadosDe(p: Pestana): EstadoCita[] {
    if (p === 'pendientes') return ['solicitada'];
    if (p === 'confirmadas') return ['confirmada'];
    return ['rechazada', 'cancelada', 'atendida', 'ausente', 'reprogramada'];
  }

  private async cargar() {
    this.cargando.set(true);
    try {
      this.lista.set(await this.citas.listar({
        estados: this.estadosDe(this.pestana()),
        texto: this.busqueda().trim() || undefined,
        fisioterapeutaId: this.auth.esFisio() ? this.auth.perfil()!.id : null,
        limite: 150,
      }));
    } catch (e) {
      this.avisos.error('No se pudieron cargar las solicitudes.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  cambiarPestana(p: Pestana) {
    this.pestana.set(p);
    void this.cargar();
  }

  buscar(e: Event) {
    this.busqueda.set((e.target as HTMLInputElement).value);
    clearTimeout(this.temporizador);
    this.temporizador = setTimeout(() => void this.cargar(), 350);
  }

  etiquetaFranja(f: string | null): string {
    return { manana: 'Por la mañana', tarde: 'Por la tarde', indistinto: 'Cualquier horario' }[f ?? ''] ?? '—';
  }

  // --- Diálogos -----------------------------------------------------------

  abrirConfirmar(c: CitaListado) {
    this.seleccion.set(c);
    this.modo.set('confirmar');
    this.errorDlg.set('');
    this.nota.set('');
    this.consultorio.set(c.consultorio ?? '');
    this.duracion.set(45);
    this.fisioSel.set(c.fisioterapeuta_id ?? '');
    this.fechaSel.set(c.fecha_solicitada);
    this.horaSel.set(c.hora_solicitada);
    this.dlgAgenda.set(true);
    void this.recargarSlots();
  }

  abrirReprogramar(c: CitaListado) {
    this.abrirConfirmar(c);
    this.modo.set('reprogramar');
    this.horaSel.set(null);
  }

  abrirRechazo(c: CitaListado) {
    this.seleccion.set(c);
    this.modo.set('rechazar');
    this.nota.set('');
    this.dlgMotivo.set(true);
  }

  abrirCancelar(c: CitaListado) {
    this.seleccion.set(c);
    this.modo.set('cancelar');
    this.nota.set('');
    this.dlgMotivo.set(true);
  }

  async verDetalle(c: CitaListado) {
    this.seleccion.set(c);
    this.enlaces.set(null);
    this.dlgDetalle.set(true);
    if (c.estado === 'confirmada' && this.auth.coordina()) {
      this.enlaces.set(await this.citas.enlaces(c.id).catch(() => null));
    }
  }

  cambiarFecha(e: Event) {
    this.fechaSel.set((e.target as HTMLInputElement).value);
    this.horaSel.set(null);
    void this.recargarSlots();
  }

  cambiarFisio(e: Event) {
    this.fisioSel.set((e.target as HTMLSelectElement).value);
    void this.recargarSlots();
  }

  private async recargarSlots() {
    if (!this.fechaSel()) return;
    this.cargandoSlots.set(true);
    try {
      this.slots.set(await this.catalogos.slots(this.fechaSel(), this.fisioSel() || null));
    } catch {
      this.slots.set([]);
    } finally {
      this.cargandoSlots.set(false);
    }
  }

  // --- Acciones -----------------------------------------------------------

  /** ISO con el desplazamiento fijo de Guatemala (UTC-6, sin horario de verano). */
  private isoGuatemala(fecha: string, hora: string): string {
    return `${fecha}T${hora.slice(0, 5)}:00-06:00`;
  }

  async guardarAgenda() {
    const c = this.seleccion();
    if (!c || !this.puedeAgendar()) return;
    this.guardando.set(true);
    this.errorDlg.set('');
    const inicio = this.isoGuatemala(this.fechaSel(), this.horaSel()!);

    try {
      const r = this.modo() === 'confirmar'
        ? await this.citas.confirmar(c.id, inicio, this.fisioSel() || null, {
            duracionMin: this.duracion(),
            consultorio: this.consultorio() || null,
            nota: this.nota() || null,
          })
        : await this.citas.reprogramar(c.id, inicio, this.fisioSel() || null, this.nota());

      if (!r.ok) {
        this.errorDlg.set(r.mensaje ?? this.textoError(r.error));
        return;
      }
      this.avisos.exito(
        (this.modo() === 'confirmar' ? 'Cita confirmada.' : 'Cita reprogramada.')
        + (this.fisioSel() ? '' : ' Quedó sin fisioterapeuta asignado.'));
      this.dlgAgenda.set(false);
      if (r.enlaces) {
        await this.copiar(
          `Confirmar: ${r.enlaces['confirmar']}\nCancelar: ${r.enlaces['cancelar']}`,
        );
        this.avisos.info('Enlaces copiados al portapapeles.');
      }
      await this.cargar();
    } catch (e) {
      this.errorDlg.set('No se pudo guardar. Intente de nuevo.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  async guardarMotivo() {
    const c = this.seleccion();
    if (!c || this.motivoCorto()) return;
    this.guardando.set(true);
    try {
      const r = this.modo() === 'rechazar'
        ? await this.citas.rechazar(c.id, this.nota())
        : await this.citas.cancelar(c.id, this.nota());
      if (!r.ok) {
        this.avisos.error(this.textoError(r.error));
        return;
      }
      this.avisos.exito(this.modo() === 'rechazar' ? 'Solicitud rechazada.' : 'Cita cancelada.');
      this.dlgMotivo.set(false);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo completar la acción.');
    } finally {
      this.guardando.set(false);
    }
  }

  async asistencia(c: CitaListado, asistio: boolean) {
    try {
      const r = await this.citas.marcarAsistencia(c.id, asistio);
      if (!r.ok) {
        this.avisos.error(r.mensaje ?? this.textoError(r.error));
        return;
      }
      this.avisos.exito(asistio
        ? 'Marcada como atendida. Ya puede llenar la nota clínica.'
        : 'Marcada como ausente.');
      await this.cargar();
    } catch (e) {
      this.avisos.error('No se pudo registrar la asistencia.');
      console.error(e);
    }
  }

  async copiarEnlaces(c: CitaListado) {
    try {
      const e = await this.citas.enlaces(c.id);
      await this.copiar(`Confirmar asistencia: ${e['confirmar']}\nCancelar: ${e['cancelar']}`);
      this.avisos.exito('Enlaces copiados. Péguelos en el mensaje al paciente.');
    } catch {
      this.avisos.error('No se pudieron generar los enlaces.');
    }
  }

  async copiar(texto: string) {
    try { await navigator.clipboard.writeText(texto); } catch { /* sin portapapeles */ }
  }

  private textoError(codigo?: string): string {
    return {
      traslape: 'Ese fisioterapeuta ya tiene una cita confirmada en ese horario.',
      falta_fisioterapeuta: 'Asigne un fisioterapeuta antes de marcarla como atendida: la nota clínica necesita autor.',
      estado_no_permite: 'La cita ya cambió de estado. Recargue la lista.',
      motivo_requerido: 'Escriba el motivo.',
    }[codigo ?? ''] ?? 'No se pudo completar la operación.';
  }
}
