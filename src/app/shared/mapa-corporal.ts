import { ChangeDetectionStrategy, Component, computed, input, model, output } from '@angular/core';
import { AreaCuerpo, AreaMarcada, VistaCuerpo } from '../core/modelos';
import { colorDolor, etiquetaDolor } from '../core/util/formato';

/**
 * Mapa corporal reutilizable.
 *
 *  - `modo="seleccion"`  → el paciente marca sus áreas de molestia (formulario público).
 *  - `modo="clinico"`    → el fisioterapeuta registra nivel de dolor por área.
 *  - `modo="lectura"`    → solo pinta lo que ya está marcado.
 *
 * La silueta es un maniquí neutro a propósito: no sugiere sexo ni complexión,
 * y las zonas se colocan sobre un viewBox fijo de 200×420 que coincide con las
 * coordenadas guardadas en `areas_cuerpo`.
 */
@Component({
  selector: 'app-mapa-corporal',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="w-full">
      @if (mostrarPestanas()) {
        <div class="flex gap-1 mb-3 p-1 bg-slate-100 rounded-lg w-fit mx-auto">
          @for (v of vistas; track v.id) {
            <button type="button" class="px-4 py-1.5 text-sm rounded-md transition-colors"
                    [class.bg-white]="vistaActiva() === v.id"
                    [class.shadow-sm]="vistaActiva() === v.id"
                    [class.font-medium]="vistaActiva() === v.id"
                    [class.text-slate-500]="vistaActiva() !== v.id"
                    (click)="vistaActiva.set(v.id)">
              {{ v.etiqueta }}
              @if (contarEn(v.id); as n) {
                <span class="ml-1.5 text-xs text-marca-700 font-semibold">{{ n }}</span>
              }
            </button>
          }
        </div>
      }

      <div class="grid gap-4" [class.sm:grid-cols-2]="!mostrarPestanas()">
        @for (v of vistasVisibles(); track v.id) {
          <figure class="relative">
            <svg viewBox="0 0 200 420" class="w-full max-w-[240px] mx-auto select-none"
                 [attr.aria-label]="'Mapa corporal, vista ' + v.etiqueta">
              <g fill="#e7ebf0" stroke="#c3ccd7" stroke-width="1.5" stroke-linejoin="round">
                <!-- cabeza y cuello -->
                <ellipse cx="100" cy="28" rx="16" ry="20" />
                <rect x="93" y="44" width="14" height="16" rx="5" />
                <!-- torso -->
                <path d="M100 58
                         C 82 58 70 62 67 70
                         C 65 76 65 86 66 96
                         C 67 106 69 112 71 118
                         C 70 140 70 164 73 188
                         L 127 188
                         C 130 164 130 140 129 118
                         C 131 112 133 106 134 96
                         C 135 86 135 76 133 70
                         C 130 62 118 58 100 58 Z" />
                <!-- brazo derecho del paciente (a la izquierda en vista anterior) -->
                <rect x="48"  y="66"  width="16" height="60" rx="8" />
                <rect x="40"  y="120" width="16" height="70" rx="8" />
                <ellipse cx="44" cy="203" rx="11" ry="15" />
                <!-- brazo izquierdo -->
                <rect x="136" y="66"  width="16" height="60" rx="8" />
                <rect x="144" y="120" width="16" height="70" rx="8" />
                <ellipse cx="156" cy="203" rx="11" ry="15" />
                <!-- pierna derecha -->
                <rect x="72"  y="184" width="22" height="80" rx="11" />
                <rect x="74"  y="256" width="18" height="94" rx="9" />
                <ellipse cx="82"  cy="364" rx="12" ry="13" />
                <!-- pierna izquierda -->
                <rect x="106" y="184" width="22" height="80" rx="11" />
                <rect x="108" y="256" width="18" height="94" rx="9" />
                <ellipse cx="118" cy="364" rx="12" ry="13" />
              </g>

              @for (a of areasDe(v.id); track a.codigo) {
                <g [attr.transform]="'translate(' + a.svg_x + ',' + a.svg_y + ')'"
                   [class.cursor-pointer]="interactivo()"
                   [attr.tabindex]="interactivo() ? 0 : null"
                   [attr.role]="interactivo() ? 'checkbox' : 'img'"
                   [attr.aria-checked]="estaMarcada(a.codigo)"
                   [attr.aria-label]="a.nombre"
                   (click)="alternar(a)"
                   (keydown.enter)="alternar(a)"
                   (keydown.space)="alternar(a); $event.preventDefault()">
                  <title>{{ a.nombre }}{{ textoNivel(a.codigo) }}</title>
                  <circle r="10" fill="transparent" />
                  <circle [attr.r]="estaMarcada(a.codigo) ? 8.5 : 5"
                          [attr.fill]="relleno(a.codigo)"
                          [attr.fill-opacity]="estaMarcada(a.codigo) ? 0.92 : 0.30"
                          [attr.stroke]="estaMarcada(a.codigo) ? '#0f172a' : '#94a3b8'"
                          [attr.stroke-width]="estaMarcada(a.codigo) ? 1.4 : 1"
                          class="transition-all duration-150" />
                  @if (estaMarcada(a.codigo) && nivelDe(a.codigo) !== null) {
                    <text y="3.5" text-anchor="middle" font-size="9" font-weight="700"
                          [attr.fill]="(nivelDe(a.codigo) ?? 0) >= 5 ? '#fff' : '#0f172a'"
                          pointer-events="none">{{ nivelDe(a.codigo) }}</text>
                  }
                </g>
              }
            </svg>
            <figcaption class="text-center text-xs text-slate-500 mt-1">{{ v.etiqueta }}</figcaption>
          </figure>
        }
      </div>

      @if (leyenda()) {
        <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5 mt-4 text-xs text-slate-500">
          <span class="font-medium text-slate-600">Intensidad:</span>
          @for (n of escala; track n) {
            <span class="inline-flex items-center gap-1.5">
              <span class="w-3 h-3 rounded-full ring-1 ring-slate-300"
                    [style.background]="color(n)"></span>{{ etiqueta(n) }}
            </span>
          }
        </div>
      }
    </div>
  `,
})
export class MapaCorporal {
  /** Catálogo completo de áreas (viene de `areas_mapa`). */
  readonly areas = input.required<AreaCuerpo[]>();
  /** Áreas marcadas. Es un `model`: el padre lo lee y lo escribe. */
  readonly seleccion = model<AreaMarcada[]>([]);
  readonly modo = input<'seleccion' | 'clinico' | 'lectura'>('seleccion');
  readonly leyenda = input(true);
  /** En móvil conviene una vista a la vez. */
  readonly pestanas = input(false);

  readonly areaTocada = output<AreaCuerpo>();

  readonly vistaActiva = model<VistaCuerpo>('anterior');

  readonly vistas: Array<{ id: VistaCuerpo; etiqueta: string }> = [
    { id: 'anterior', etiqueta: 'Frente' },
    { id: 'posterior', etiqueta: 'Espalda' },
  ];
  readonly escala = [0, 3, 5, 7, 9];

  readonly interactivo = computed(() => this.modo() !== 'lectura');
  readonly mostrarPestanas = computed(() => this.pestanas());

  readonly vistasVisibles = computed(() =>
    this.mostrarPestanas() ? this.vistas.filter((v) => v.id === this.vistaActiva()) : this.vistas,
  );

  areasDe(vista: VistaCuerpo): AreaCuerpo[] {
    return this.areas().filter((a) => a.vista === vista);
  }

  contarEn(vista: VistaCuerpo): number {
    const codigos = new Set(this.areasDe(vista).map((a) => a.codigo));
    return this.seleccion().filter((s) => codigos.has(s.codigo)).length;
  }

  estaMarcada(codigo: string): boolean {
    return this.seleccion().some((s) => s.codigo === codigo);
  }

  nivelDe(codigo: string): number | null {
    const m = this.seleccion().find((s) => s.codigo === codigo);
    if (!m) return null;
    const n = m.nivel_dolor ?? m.intensidad;
    return n ?? null;
  }

  relleno(codigo: string): string {
    if (!this.estaMarcada(codigo)) return '#64748b';
    return colorDolor(this.nivelDe(codigo) ?? 5);
  }

  textoNivel(codigo: string): string {
    const n = this.nivelDe(codigo);
    return n === null ? '' : ` · dolor ${n}/10 (${etiquetaDolor(n)})`;
  }

  color = colorDolor;
  etiqueta = etiquetaDolor;

  alternar(area: AreaCuerpo): void {
    if (!this.interactivo()) return;
    this.areaTocada.emit(area);

    const actual = this.seleccion();
    if (this.estaMarcada(area.codigo)) {
      this.seleccion.set(actual.filter((s) => s.codigo !== area.codigo));
      return;
    }
    const nueva: AreaMarcada = {
      codigo: area.codigo,
      nombre: area.nombre,
      vista: area.vista,
      svg_x: area.svg_x,
      svg_y: area.svg_y,
      ...(this.modo() === 'clinico' ? { nivel_dolor: 5 } : { intensidad: 5 }),
    };
    this.seleccion.set([...actual, nueva]);
  }
}
