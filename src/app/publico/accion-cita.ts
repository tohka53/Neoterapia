import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CitasService } from '../core/api/citas.service';
import { fechaLarga, horaCorta } from '../core/util/formato';
import { Cargando, EscalaDolor } from '../shared/ui';

/**
 * Pantalla que abre el paciente al tocar un enlace del mensaje.
 *
 * El token viaja en la query (`?t=`), se verifica contra su hash en la base y
 * solo habilita la acción para la que fue emitido. Nunca muestra expediente,
 * historial ni datos de otras citas.
 */
@Component({
  selector: 'app-accion-cita',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Cargando, EscalaDolor],
  template: `
    <div class="mx-auto max-w-lg px-4 py-12">
      <div class="tarjeta tarjeta-cuerpo">

        @if (cargando()) {
          <app-cargando texto="Verificando su enlace…" />

        } @else if (error()) {
          <div class="text-center py-4">
            <div class="mx-auto w-12 h-12 rounded-full bg-rose-100 grid place-items-center">
              <span class="text-rose-600 text-2xl leading-none">!</span>
            </div>
            <h1 class="mt-4 text-xl font-semibold">{{ tituloError() }}</h1>
            <p class="mt-2 text-slate-600">{{ textoError() }}</p>
            <a routerLink="/solicitar" class="btn-primario mt-6">Solicitar una cita nueva</a>
          </div>

        } @else if (listo()) {
          <div class="text-center py-4">
            <div class="mx-auto w-12 h-12 rounded-full bg-marca-100 grid place-items-center">
              <svg viewBox="0 0 24 24" class="w-6 h-6 text-marca-700" fill="none" stroke="currentColor" stroke-width="2.5">
                <path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7"/>
              </svg>
            </div>
            <h1 class="mt-4 text-xl font-semibold">Listo</h1>
            <p class="mt-2 text-slate-600">{{ mensajeFinal() }}</p>
            <a routerLink="/" class="btn-secundario mt-6">Volver al inicio</a>
          </div>

        } @else {
          <!-- Confirmación de la acción -->
          <h1 class="text-xl font-semibold">{{ titulo() }}</h1>
          @if (saludo()) { <p class="mt-1 text-slate-600">Hola, {{ saludo() }}.</p> }

          @if (cuando()) {
            <div class="mt-5 rounded-lg bg-slate-50 ring-1 ring-slate-200 px-4 py-3">
              <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">Su cita</p>
              <p class="mt-1 text-slate-800 capitalize">{{ cuando() }}</p>
              <p class="text-sm text-slate-500 font-mono mt-0.5">{{ codigo() }}</p>
            </div>
          }

          @if (accion() === 'cancelar') {
            <div class="mt-5">
              <label class="etiqueta" for="motivo">¿Nos cuenta por qué? (opcional)</label>
              <textarea id="motivo" class="campo" rows="2" maxlength="300"
                        (input)="motivo.set($any($event.target).value)"></textarea>
            </div>
          }

          @if (accion() === 'evaluacion') {
            <div class="mt-5 space-y-5">
              <div>
                <span class="etiqueta">¿Cómo califica su sesión?</span>
                <div class="flex gap-2">
                  @for (n of [1,2,3,4,5]; track n) {
                    <button type="button"
                            class="flex-1 py-3 rounded-lg text-xl ring-1 transition-colors"
                            [class]="puntuacion() >= n
                              ? 'bg-amber-50 ring-amber-300 text-amber-500'
                              : 'bg-white ring-slate-200 text-slate-300'"
                            [attr.aria-label]="n + ' de 5'"
                            (click)="puntuacion.set(n)">★</button>
                  }
                </div>
              </div>
              <app-escala-dolor [(valor)]="dolor" titulo="¿Cómo está su dolor ahora?" />
              <div>
                <label class="etiqueta" for="c">Comentarios</label>
                <textarea id="c" class="campo" rows="3" maxlength="500"
                          (input)="comentario.set($any($event.target).value)"></textarea>
              </div>
            </div>
          }

          @if (mensajeError()) {
            <p class="mt-4 rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
              {{ mensajeError() }}
            </p>
          }

          <div class="mt-6 flex gap-3">
            <button type="button" class="flex-1"
                    [class]="accion() === 'cancelar' ? 'btn-peligro' : 'btn-primario'"
                    [disabled]="procesando() || (accion() === 'evaluacion' && puntuacion() === 0)"
                    (click)="ejecutar()">
              {{ procesando() ? 'Procesando…' : textoBoton() }}
            </button>
            <a routerLink="/" class="btn-secundario">Salir</a>
          </div>

          <p class="mt-4 text-xs text-slate-400 text-center">
            Este enlace solo sirve para esta acción y vence pronto. No da acceso a su expediente.
          </p>
        }
      </div>
    </div>
  `,
})
export class AccionCita {
  private readonly citas = inject(CitasService);

  /** Segmento de la ruta: confirmar | cancelar | evaluacion | calendario */
  readonly accion = input<string>('confirmar');
  /** `?t=` con el token. Llega por `withComponentInputBinding`. */
  readonly t = input<string>('');

  readonly cargando = signal(true);
  readonly procesando = signal(false);
  readonly listo = signal(false);
  readonly error = signal<string | null>(null);
  readonly mensajeError = signal('');
  readonly mensajeFinal = signal('');

  readonly codigo = signal('');
  readonly saludo = signal('');
  readonly inicio = signal<string | null>(null);
  readonly fechaSolicitada = signal<string | null>(null);

  readonly motivo = signal('');
  readonly puntuacion = signal(0);
  readonly dolor = signal(0);
  readonly comentario = signal('');

  constructor() {
    queueMicrotask(() => void this.cargar());
  }

  private async cargar() {
    const token = this.t();
    if (!token) {
      this.error.set('token_invalido');
      this.cargando.set(false);
      return;
    }
    try {
      const r = await this.citas.contextoEnlace(token);
      if (!r?.['ok']) {
        this.error.set((r?.['error'] as string) ?? 'token_invalido');
      } else {
        this.codigo.set(String(r['codigo_referencia'] ?? ''));
        this.saludo.set(String(r['saludo'] ?? ''));
        this.inicio.set((r['inicio'] as string) ?? null);
        this.fechaSolicitada.set((r['fecha_solicitada'] as string) ?? null);
      }
    } catch {
      this.error.set('token_invalido');
    } finally {
      this.cargando.set(false);
    }
  }

  readonly titulo = computed(() => ({
    confirmar: 'Confirmar su asistencia',
    cancelar: 'Cancelar su cita',
    evaluacion: 'Su opinión nos ayuda',
    calendario: 'Agregar a su calendario',
  } as Record<string, string>)[this.accion()] ?? 'Su cita');

  readonly textoBoton = computed(() => ({
    confirmar: 'Sí, voy a asistir',
    cancelar: 'Cancelar la cita',
    evaluacion: 'Enviar evaluación',
    calendario: 'Descargar el evento',
  } as Record<string, string>)[this.accion()] ?? 'Continuar');

  readonly cuando = computed(() => {
    const i = this.inicio();
    if (i) return `${fechaLarga(i)} · ${horaCorta(i)}`;
    const f = this.fechaSolicitada();
    return f ? fechaLarga(`${f}T12:00:00`) : '';
  });

  readonly tituloError = computed(() => ({
    enlace_vencido: 'Este enlace ya venció',
    enlace_agotado: 'Este enlace ya fue usado',
    enlace_revocado: 'Este enlace ya no está activo',
    estado_no_permite: 'La cita cambió de estado',
  } as Record<string, string>)[this.error() ?? ''] ?? 'Enlace no válido');

  readonly textoError = computed(() => ({
    enlace_vencido: 'Por seguridad los enlaces vencen. Escríbanos con su código de referencia y le ayudamos.',
    enlace_agotado: 'Ya registramos su respuesta. Si necesita cambiar algo, comuníquese con la clínica.',
    enlace_revocado: 'Es posible que se haya reprogramado o cancelado la cita. Revise el mensaje más reciente.',
    estado_no_permite: 'Esta cita ya fue atendida, cancelada o reprogramada. Consulte con la clínica.',
  } as Record<string, string>)[this.error() ?? '']
    ?? 'No pudimos verificar el enlace. Comuníquese con la clínica citando su código de referencia.');

  async ejecutar() {
    if (this.accion() === 'calendario') {
      this.descargarIcs();
      return;
    }
    this.procesando.set(true);
    this.mensajeError.set('');
    try {
      const datos: Record<string, unknown> = {};
      if (this.accion() === 'cancelar') datos['motivo'] = this.motivo().trim() || null;
      if (this.accion() === 'evaluacion') {
        datos['puntuacion'] = this.puntuacion();
        datos['dolor_reportado'] = this.dolor();
        datos['comentario'] = this.comentario().trim() || null;
      }
      const r = await this.citas.usarEnlace(this.t(), datos);
      if (!r?.['ok']) {
        this.error.set((r?.['error'] as string) ?? 'token_invalido');
        return;
      }
      this.mensajeFinal.set(String(r['mensaje'] ?? 'Gracias.'));
      this.listo.set(true);
    } catch {
      this.mensajeError.set('No pudimos procesar su solicitud. Intente de nuevo.');
    } finally {
      this.procesando.set(false);
    }
  }

  /** Archivo .ics generado en el navegador: no necesita servidor. */
  private descargarIcs() {
    const inicio = this.inicio();
    if (!inicio) return;
    const ini = new Date(inicio);
    const fin = new Date(ini.getTime() + 45 * 60000);
    const f = (d: Date) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const ics = [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//NeoTerapia//ES', 'BEGIN:VEVENT',
      `UID:${this.codigo()}@neoterapia`,
      `DTSTAMP:${f(new Date())}`,
      `DTSTART:${f(ini)}`,
      `DTEND:${f(fin)}`,
      'SUMMARY:Cita de fisioterapia · NeoTerapia',
      `DESCRIPTION:Código de referencia ${this.codigo()}`,
      'BEGIN:VALARM', 'TRIGGER:-PT2H', 'ACTION:DISPLAY',
      'DESCRIPTION:Su cita de fisioterapia es en 2 horas', 'END:VALARM',
      'END:VEVENT', 'END:VCALENDAR',
    ].join('\r\n');

    const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `cita-${this.codigo()}.ics`;
    a.click();
    URL.revokeObjectURL(url);
    this.mensajeFinal.set('Se descargó el evento. Ábralo para agregarlo a su calendario.');
    this.listo.set(true);
  }
}
