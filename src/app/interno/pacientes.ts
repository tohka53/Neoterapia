import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { PacientesService } from '../core/api/pacientes.service';
import { PacienteListado, Perfil } from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import {
  esEmailValido, fechaCorta, formatearDpi, formatearTelefono, validarDpi,
} from '../core/util/formato';
import { Cargando, Dialogo, Vacio } from '../shared/ui';

@Component({
  selector: 'app-pacientes',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Dialogo, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="flex flex-wrap items-end justify-between gap-4 mb-5">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Pacientes</h1>
          <p class="text-sm text-slate-500 mt-0.5">
            Las fichas se crean solas al recibir una solicitud. El DPI se muestra enmascarado.
          </p>
        </div>
        @if (auth.coordina()) {
          <button type="button" class="btn-primario" (click)="abrirAlta()">Registrar paciente</button>
        }
      </header>

      <div class="flex flex-wrap gap-2 mb-4">
        <input class="campo max-w-sm" placeholder="Buscar por nombre, DPI, teléfono o correo…"
               [value]="busqueda()" (input)="buscar($event)">
        @if (auth.esAdmin()) {
          <select class="campo w-40 py-2" [value]="estado()" (change)="cambiarEstado($event)">
            <option value="">Activos</option>
            <option value="inactivo">Inactivos</option>
            <option value="fusionado">Fusionados</option>
          </select>
        }
      </div>

      @if (cargando()) {
        <app-cargando />
      } @else if (lista().length === 0) {
        <div class="tarjeta">
          <app-vacio titulo="Sin resultados"
                     detalle="Pruebe con otro término o registre al paciente." />
        </div>
      } @else {
        <div class="tarjeta overflow-hidden">
          <div class="overflow-x-auto">
            <table class="tabla">
              <thead>
                <tr>
                  <th>Paciente</th>
                  <th>Documento</th>
                  <th>Contacto</th>
                  <th>Fisioterapeuta</th>
                  <th class="text-right">Citas</th>
                  <th>Última visita</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                @for (p of lista(); track p.id) {
                  <tr>
                    <td>
                      <a [routerLink]="['/panel/pacientes', p.id]"
                         class="font-medium hover:text-marca-700">{{ p.nombre_completo }}</a>
                      <div class="flex items-center gap-1.5 mt-0.5">
                        @if (p.alta_automatica) {
                          <span class="chip-neutro text-[10px]">Alta automática</span>
                        }
                        @if (p.estado === 'fusionado') {
                          <span class="chip bg-indigo-50 text-indigo-800 ring-indigo-200 text-[10px]">Fusionada</span>
                        }
                        @if (p.alertas_pendientes > 0) {
                          <span class="chip bg-amber-50 text-amber-800 ring-amber-200 text-[10px]">
                            ⚠ {{ p.alertas_pendientes }}
                          </span>
                        }
                        @if (!p.dpi_valido) {
                          <span class="chip bg-rose-50 text-rose-800 ring-rose-200 text-[10px]">DPI dudoso</span>
                        }
                      </div>
                    </td>
                    <td class="dpi whitespace-nowrap">{{ p.dpi_mascara }}</td>
                    <td class="text-xs">
                      @if (p.telefono) { <div>{{ tel(p.telefono) }}</div> }
                      @if (p.email) { <div class="text-slate-500 truncate max-w-44">{{ p.email }}</div> }
                      @if (!p.telefono && !p.email) { <span class="text-slate-400">—</span> }
                    </td>
                    <td class="text-sm">{{ p.fisioterapeuta ?? '—' }}</td>
                    <td class="text-right tabular-nums">
                      {{ p.citas_totales }}
                      @if (p.ausencias > 0) {
                        <span class="text-xs text-orange-600 ml-1">({{ p.ausencias }} faltas)</span>
                      }
                    </td>
                    <td class="text-sm whitespace-nowrap">
                      {{ p.ultima_visita ? fecha(p.ultima_visita) : '—' }}
                      @if (p.proxima_cita) {
                        <div class="text-xs text-marca-700">Próx. {{ fecha(p.proxima_cita) }}</div>
                      }
                    </td>
                    <td class="text-right">
                      <a [routerLink]="['/panel/pacientes', p.id]" class="btn-fantasma btn-sm">Abrir</a>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        </div>
      }
    </div>

    <!-- Alta manual -->
    <app-dialogo [(abierto)]="dlgAlta" titulo="Registrar paciente"
                 subtitulo="Para altas por teléfono o en mostrador" ancho="lg">
      <div class="space-y-4">
        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="etiqueta" for="ndpi">DPI</label>
            <input id="ndpi" class="campo font-mono" [class.campo-error]="dpi() !== '' && !dpiOk()"
                   inputmode="numeric" placeholder="0000 00000 0000"
                   [value]="dpi()" (input)="escribirDpi($event)">
            @if (dpi() !== '' && !dpiOk()) { <p class="error-texto">{{ errorDpi() }}</p> }
          </div>
          <div>
            <label class="etiqueta" for="nnom">Nombre completo</label>
            <input id="nnom" class="campo" [value]="nombre()"
                   (input)="nombre.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="ntel">Teléfono</label>
            <input id="ntel" class="campo" [value]="telefono()"
                   (input)="telefono.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="nwa">WhatsApp</label>
            <input id="nwa" class="campo" [value]="whatsapp()"
                   (input)="whatsapp.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="nmail">Correo</label>
            <input id="nmail" class="campo" type="email" [value]="email()"
                   (input)="email.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="nnac">Fecha de nacimiento</label>
            <input id="nnac" class="campo" type="date" [value]="nacimiento()"
                   (input)="nacimiento.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="nfis">Fisioterapeuta principal</label>
            <select id="nfis" class="campo" [value]="fisio()"
                    (change)="fisio.set($any($event.target).value)">
              <option value="">Sin asignar</option>
              @for (f of fisios(); track f.id) {
                <option [value]="f.id">{{ f.nombre_completo }}</option>
              }
            </select>
          </div>
          <div>
            <label class="etiqueta" for="nsex">Sexo</label>
            <select id="nsex" class="campo" [value]="sexo()"
                    (change)="sexo.set($any($event.target).value)">
              <option value="">Sin indicar</option>
              <option value="F">Femenino</option>
              <option value="M">Masculino</option>
              <option value="X">Otro</option>
            </select>
          </div>
        </div>

        @if (errorAlta()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorAlta() }}
            @if (idExistente()) {
              <a [routerLink]="['/panel/pacientes', idExistente()]" class="underline ml-1"
                 (click)="dlgAlta.set(false)">Abrir la ficha existente</a>
            }
          </p>
        }
      </div>

      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAlta.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!altaValida() || guardando()"
                (click)="guardarAlta()">
          {{ guardando() ? 'Guardando…' : 'Registrar' }}
        </button>
      </div>
    </app-dialogo>
  `,
})
export class Pacientes {
  private readonly pacientes = inject(PacientesService);
  private readonly catalogos = inject(CatalogosService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly cargando = signal(true);
  readonly lista = signal<PacienteListado[]>([]);
  readonly busqueda = signal('');
  readonly estado = signal('');
  readonly fisios = signal<Perfil[]>([]);

  readonly dlgAlta = signal(false);
  readonly guardando = signal(false);
  readonly errorAlta = signal('');
  readonly idExistente = signal<string | null>(null);

  readonly dpi = signal('');
  readonly nombre = signal('');
  readonly telefono = signal('');
  readonly whatsapp = signal('');
  readonly email = signal('');
  readonly nacimiento = signal('');
  readonly sexo = signal('');
  readonly fisio = signal('');

  readonly fecha = fechaCorta;
  readonly tel = formatearTelefono;

  private temporizador?: ReturnType<typeof setTimeout>;

  readonly dpiOk = computed(() => validarDpi(this.dpi()).valido);
  readonly errorDpi = computed(() => validarDpi(this.dpi()).mensaje ?? '');
  readonly altaValida = computed(() =>
    this.dpiOk()
    && this.nombre().trim().split(/\s+/).length >= 2
    && (this.email() === '' || esEmailValido(this.email())),
  );

  constructor() {
    void this.catalogos.fisioterapeutas().then((f) => this.fisios.set(f));
    void this.cargar();
  }

  private async cargar() {
    this.cargando.set(true);
    try {
      this.lista.set(await this.pacientes.listar({
        texto: this.busqueda().trim() || undefined,
        estado: this.estado() || undefined,
        fisioterapeutaId: this.auth.esFisio() ? this.auth.perfil()!.id : null,
      }));
    } catch (e) {
      this.avisos.error('No se pudieron cargar los pacientes.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  buscar(e: Event) {
    this.busqueda.set((e.target as HTMLInputElement).value);
    clearTimeout(this.temporizador);
    this.temporizador = setTimeout(() => void this.cargar(), 350);
  }

  cambiarEstado(e: Event) {
    this.estado.set((e.target as HTMLSelectElement).value);
    void this.cargar();
  }

  escribirDpi(e: Event) {
    this.dpi.set(formatearDpi((e.target as HTMLInputElement).value));
  }

  abrirAlta() {
    this.dpi.set(''); this.nombre.set(''); this.telefono.set(''); this.whatsapp.set('');
    this.email.set(''); this.nacimiento.set(''); this.sexo.set(''); this.fisio.set('');
    this.errorAlta.set(''); this.idExistente.set(null);
    this.dlgAlta.set(true);
  }

  async guardarAlta() {
    if (!this.altaValida()) return;
    this.guardando.set(true);
    this.errorAlta.set('');
    this.idExistente.set(null);
    try {
      const r = await this.pacientes.registrar({
        dpi: this.dpi().replace(/\D/g, ''),
        tipo_documento: 'dpi',
        nombre_completo: this.nombre().trim(),
        telefono: this.telefono().trim() || null,
        whatsapp: this.whatsapp().trim() || null,
        email: this.email().trim() || null,
        fecha_nacimiento: this.nacimiento() || null,
        sexo: this.sexo() || null,
        fisioterapeuta_id: this.fisio() || null,
      });
      if (!r.ok) {
        if (r.error === 'documento_existente') {
          this.errorAlta.set('Ya existe una ficha con ese documento.');
          this.idExistente.set((r as { paciente_id?: string }).paciente_id ?? null);
        } else {
          this.errorAlta.set('El documento no es válido.');
        }
        return;
      }
      this.avisos.exito('Paciente registrado.');
      this.dlgAlta.set(false);
      await this.cargar();
    } catch (e) {
      this.errorAlta.set('No se pudo registrar. Revise los datos.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }
}
