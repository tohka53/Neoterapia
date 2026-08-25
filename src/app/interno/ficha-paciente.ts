import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { CitasService } from '../core/api/citas.service';
import { ClinicaService } from '../core/api/clinica.service';
import { PacientesService } from '../core/api/pacientes.service';
import {
  Alerta, AreaMarcada, CitaListado, ETIQUETAS_ALERTA, MetodoPago, MomentoMapa,
  PacienteListado, Pago, Perfil, PuntoEvolucion, SesionDetalle,
} from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import {
  colorDolor, fechaCorta, fechaHora, formatearDpi, formatearTelefono, haceCuanto,
  horaCorta, iniciales, moneda, validarDpi,
} from '../core/util/formato';
import { MapaCorporal } from '../shared/mapa-corporal';
import { Cargando, ChipEstado, Dialogo, Vacio } from '../shared/ui';

type Pestana = 'resumen' | 'citas' | 'clinico' | 'evolucion' | 'pagos' | 'identidad';

@Component({
  selector: 'app-ficha-paciente',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ChipEstado, Dialogo, Cargando, Vacio, MapaCorporal],
  template: `
    @if (cargando()) {
      <app-cargando texto="Abriendo la ficha…" />
    } @else if (!paciente()) {
      <div class="p-8"><app-vacio titulo="No se encontró el paciente"
        detalle="Puede que la ficha se haya fusionado con otra o que no tenga permiso para verla." /></div>
    } @else {
      <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">

        <!-- ============ Encabezado ============ -->
        <header class="tarjeta tarjeta-cuerpo mb-5">
          <div class="flex flex-wrap items-start gap-4">
            <span class="w-14 h-14 rounded-full bg-marca-100 text-marca-800 grid place-items-center
                         text-lg font-semibold shrink-0">{{ ini() }}</span>

            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h1 class="text-2xl font-bold tracking-tight">{{ paciente()!.nombre_completo }}</h1>
                @if (paciente()!.estado === 'fusionado') {
                  <span class="chip bg-indigo-50 text-indigo-800 ring-indigo-200">Ficha fusionada</span>
                }
                @if (paciente()!.alta_automatica) {
                  <span class="chip-neutro">Alta automática</span>
                }
              </div>

              <div class="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-slate-600">
                <span class="inline-flex items-center gap-2">
                  <span class="dpi">{{ dpiVisible() ?? paciente()!.dpi_mascara }}</span>
                  @if (puedeVerDpi()) {
                    <button type="button" class="text-xs text-marca-700 hover:underline"
                            (click)="dpiVisible() ? ocultarDpi() : abrirVerDpi()">
                      {{ dpiVisible() ? 'Ocultar' : 'Ver completo' }}
                    </button>
                  }
                  @if (!paciente()!.dpi_valido) {
                    <span class="chip bg-rose-50 text-rose-800 ring-rose-200 text-[10px]">No pasa validación</span>
                  }
                </span>
                @if (paciente()!.telefono) { <span>{{ tel(paciente()!.telefono) }}</span> }
                @if (paciente()!.email) { <span>{{ paciente()!.email }}</span> }
                @if (paciente()!.edad) { <span>{{ paciente()!.edad }} años</span> }
              </div>

              <p class="mt-1 text-xs text-slate-400">
                Ficha creada el {{ fecha(paciente()!.creado_en) }} ·
                {{ paciente()!.citas_totales }} cita(s) ·
                fisioterapeuta: {{ paciente()!.fisioterapeuta ?? 'sin asignar' }}
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              @if (auth.coordina()) {
                <button type="button" class="btn-secundario btn-sm" (click)="abrirEditar()">Editar datos</button>
              }
              @if (auth.esAdmin()) {
                <button type="button" class="btn-secundario btn-sm" (click)="abrirCorregirDpi()">Corregir DPI</button>
              }
              <button type="button" class="btn-fantasma btn-sm no-imprimir" (click)="imprimir()">Imprimir</button>
            </div>
          </div>

          @if (alertas().length) {
            <div class="mt-4 space-y-2">
              @for (a of alertas(); track a.id) {
                <div class="rounded-lg px-3 py-2.5 text-sm flex items-start gap-3 ring-1"
                     [class]="a.severidad === 3
                       ? 'bg-rose-50 ring-rose-200 text-rose-900'
                       : 'bg-amber-50 ring-amber-200 text-amber-900'">
                  <span class="shrink-0 font-semibold">⚠</span>
                  <div class="flex-1 min-w-0">
                    <p class="font-medium">{{ a.titulo }}</p>
                    <p class="text-xs opacity-80">{{ etiquetaAlerta(a.tipo) }} · {{ cuando(a.creado_en) }}</p>
                    @if (a.detalle && objeto(a.detalle).length) {
                      <dl class="mt-1 text-xs grid sm:grid-cols-2 gap-x-4">
                        @for (d of objeto(a.detalle); track d.k) {
                          <div class="flex gap-1.5"><dt class="opacity-70">{{ d.k }}:</dt><dd>{{ d.v }}</dd></div>
                        }
                      </dl>
                    }
                  </div>
                  @if (auth.coordina()) {
                    <button type="button" class="btn-fantasma btn-sm shrink-0"
                            (click)="resolverAlerta(a)">Marcar revisada</button>
                  }
                </div>
              }
            </div>
          }
        </header>

        <!-- ============ Pestañas ============ -->
        <div class="flex gap-1 p-1 bg-slate-100 rounded-lg w-fit mb-5 overflow-x-auto no-imprimir">
          @for (p of pestanasVisibles(); track p.id) {
            <button type="button" class="px-4 py-1.5 text-sm rounded-md whitespace-nowrap transition-colors"
                    [class]="pestana() === p.id ? 'bg-white shadow-sm font-medium' : 'text-slate-500'"
                    (click)="pestana.set(p.id)">{{ p.etiqueta }}</button>
          }
        </div>

        <!-- ---------- Resumen ---------- -->
        @if (pestana() === 'resumen') {
          <div class="grid gap-5 lg:grid-cols-3">
            <section class="tarjeta tarjeta-cuerpo lg:col-span-2">
              <h2 class="font-semibold mb-3">Datos de contacto</h2>
              <dl class="divide-y divide-slate-100 text-sm">
                @for (f of datosContacto(); track f.k) {
                  <div class="py-2.5 grid grid-cols-3 gap-3">
                    <dt class="text-slate-500">{{ f.k }}</dt>
                    <dd class="col-span-2">{{ f.v }}</dd>
                  </div>
                }
              </dl>
            </section>

            <section class="tarjeta tarjeta-cuerpo">
              <h2 class="font-semibold mb-3">Resumen</h2>
              <dl class="space-y-2.5 text-sm">
                <div class="flex justify-between"><dt class="text-slate-500">Citas totales</dt>
                  <dd class="font-semibold tabular-nums">{{ paciente()!.citas_totales }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Inasistencias</dt>
                  <dd class="font-semibold tabular-nums" [class.text-orange-600]="paciente()!.ausencias > 0">
                    {{ paciente()!.ausencias }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Última visita</dt>
                  <dd>{{ paciente()!.ultima_visita ? fecha(paciente()!.ultima_visita) : '—' }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Próxima cita</dt>
                  <dd>{{ paciente()!.proxima_cita ? fecha(paciente()!.proxima_cita) : '—' }}</dd></div>
                @if (auth.veFinanzas() && saldo(); as s) {
                  <div class="pt-2.5 border-t border-slate-100 flex justify-between">
                    <dt class="text-slate-500">Saldo</dt>
                    <dd class="font-semibold tabular-nums" [class.text-rose-600]="s.saldo > 0">
                      {{ dinero(s.saldo) }}</dd>
                  </div>
                }
              </dl>
            </section>
          </div>
        }

        <!-- ---------- Citas ---------- -->
        @if (pestana() === 'citas') {
          <div class="tarjeta overflow-hidden">
            @if (citasLista().length === 0) {
              <app-vacio titulo="Sin citas registradas" />
            } @else {
              <div class="overflow-x-auto">
                <table class="tabla">
                  <thead><tr>
                    <th>Código</th><th>Fecha</th><th>Estado</th><th>Fisioterapeuta</th>
                    <th>Áreas</th><th></th>
                  </tr></thead>
                  <tbody>
                    @for (c of citasLista(); track c.id) {
                      <tr>
                        <td class="font-mono text-xs">{{ c.codigo_referencia }}</td>
                        <td class="whitespace-nowrap">
                          {{ c.inicio_programado ? fecha(c.inicio_programado) : fecha(c.fecha_solicitada + 'T12:00:00') }}
                          @if (c.inicio_programado) {
                            <span class="text-slate-400 text-xs">{{ hora(c.inicio_programado) }}</span>
                          }
                        </td>
                        <td><app-chip-estado [estado]="c.estado" /></td>
                        <td class="text-sm">{{ c.fisioterapeuta ?? '—' }}</td>
                        <td class="text-xs">
                          <div class="flex flex-wrap gap-1">
                            @for (a of c.areas; track a.codigo) {
                              <span class="inline-flex items-center gap-1">
                                <span class="w-2 h-2 rounded-full" [style.background]="color(a.intensidad ?? 0)"></span>
                                {{ a.nombre }}
                              </span>
                            }
                          </div>
                        </td>
                        <td class="text-right">
                          @if (c.motivo_estado) {
                            <span class="text-xs text-slate-400" [title]="c.motivo_estado">motivo</span>
                          }
                        </td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
            }
          </div>
        }

        <!-- ---------- Historial clínico ---------- -->
        @if (pestana() === 'clinico' && auth.veClinico()) {
          <div class="space-y-5">
            <section class="tarjeta tarjeta-cuerpo">
              <div class="flex items-center justify-between mb-3">
                <h2 class="font-semibold">Antecedentes</h2>
                <button type="button" class="btn-secundario btn-sm" (click)="guardarClinico()"
                        [disabled]="guardando()">Guardar</button>
              </div>
              <div class="grid gap-4 sm:grid-cols-2">
                @for (c of camposClinicos; track c.campo) {
                  <div [class.sm:col-span-2]="c.ancho">
                    <label class="etiqueta" [attr.for]="c.campo">{{ c.etiqueta }}</label>
                    <textarea [id]="c.campo" class="campo" rows="2"
                              (input)="setClinico(c.campo, $any($event.target).value)"
                    >{{ clinico()[c.campo] ?? '' }}</textarea>
                  </div>
                }
              </div>
            </section>

            <section class="tarjeta overflow-hidden">
              <header class="px-5 py-4 border-b border-slate-100">
                <h2 class="font-semibold">Sesiones ({{ sesiones().length }})</h2>
              </header>
              @if (sesiones().length === 0) {
                <app-vacio titulo="Sin sesiones registradas"
                           detalle="Al marcar una cita como atendida se abre la nota clínica." />
              } @else {
                <ul class="divide-y divide-slate-100">
                  @for (s of sesiones(); track s.id) {
                    <li class="px-5 py-4">
                      <div class="flex flex-wrap items-start justify-between gap-3">
                        <div class="min-w-0">
                          <p class="font-medium text-sm">
                            {{ fecha(s.inicio) }} · {{ hora(s.inicio) }}
                            @if (s.firmada_en) {
                              <span class="chip bg-emerald-50 text-emerald-800 ring-emerald-200 ml-2">Firmada</span>
                            } @else {
                              <span class="chip bg-amber-50 text-amber-800 ring-amber-200 ml-2">Borrador</span>
                            }
                          </p>
                          <p class="text-xs text-slate-500 mt-0.5">
                            {{ s.fisioterapeuta }} · {{ s.codigo_referencia }}
                            @if (s.dolor_inicial !== null) {
                              · dolor {{ s.dolor_inicial }} → {{ s.dolor_final ?? '?' }}
                            }
                          </p>
                        </div>
                        <a [routerLink]="['/panel/sesiones', s.id]" class="btn-secundario btn-sm">
                          {{ s.firmada_en ? 'Ver' : 'Continuar' }}
                        </a>
                      </div>
                      @if (s.analisis || s.plan) {
                        <p class="mt-2 text-sm text-slate-700 line-clamp-2">
                          {{ s.analisis || s.plan }}
                        </p>
                      }
                      @if (s.tratamientos.length) {
                        <div class="mt-2 flex flex-wrap gap-1.5">
                          @for (t of s.tratamientos; track t.id) {
                            <span class="chip-neutro">{{ t.nombre }} ×{{ t.cantidad }}</span>
                          }
                        </div>
                      }
                    </li>
                  }
                </ul>
              }
            </section>
          </div>
        }

        <!-- ---------- Evolución ---------- -->
        @if (pestana() === 'evolucion') {
          @if (momentos().length === 0) {
            <div class="tarjeta">
              <app-vacio titulo="Todavía no hay mapas registrados"
                         detalle="El primero se crea con la solicitud del paciente; los siguientes, en cada sesión." />
            </div>
          } @else {
            <!-- Línea de tiempo -->
            <div class="tarjeta tarjeta-cuerpo mb-5">
              <div class="flex items-baseline justify-between gap-4 mb-3">
                <h2 class="font-semibold">Historial del mapa corporal</h2>
                <span class="text-sm text-slate-500">
                  {{ momentos().length }} registro{{ momentos().length > 1 ? 's' : '' }}
                </span>
              </div>
              <div class="flex gap-2 overflow-x-auto pb-2">
                @for (m of momentos(); track m.momento_id; let i = $index) {
                  <button type="button"
                          class="shrink-0 w-40 rounded-lg ring-1 px-3 py-2.5 text-left transition-colors"
                          [class]="indiceSel() === i
                            ? 'bg-marca-50 ring-marca-500'
                            : 'bg-white ring-slate-200 hover:bg-slate-50'"
                          (click)="indiceSel.set(i)">
                    <div class="flex items-center justify-between gap-2">
                      <span class="text-xs font-medium"
                            [class]="m.momento_tipo === 'solicitud' ? 'text-slate-500' : 'text-marca-700'">
                        {{ m.momento_tipo === 'solicitud' ? 'Solicitud' : 'Sesión ' + numeroSesion(i) }}
                      </span>
                      @if (i === momentos().length - 1) {
                        <span class="chip-neutro text-[10px]">Actual</span>
                      }
                    </div>
                    <p class="text-sm font-semibold mt-0.5">{{ fecha(m.fecha) }}</p>
                    <div class="flex items-center gap-1.5 mt-1.5">
                      <span class="w-2.5 h-2.5 rounded-full shrink-0"
                            [style.background]="color(m.dolor_maximo)"></span>
                      <span class="text-xs text-slate-500">
                        máx {{ m.dolor_maximo }}/10 · {{ m.areas.length }} zona{{ m.areas.length > 1 ? 's' : '' }}
                      </span>
                    </div>
                  </button>
                }
              </div>
            </div>

            <div class="grid gap-5 lg:grid-cols-2">
              <!-- Mapa del momento seleccionado -->
              <section class="tarjeta tarjeta-cuerpo">
                @if (momentoSel(); as m) {
                  <div class="flex items-start justify-between gap-3 mb-1">
                    <div>
                      <h2 class="font-semibold">
                        {{ m.momento_tipo === 'solicitud' ? 'Lo que marcó el paciente' : 'Registro de la sesión' }}
                      </h2>
                      <p class="text-sm text-slate-500 mt-0.5">
                        {{ fechaYHora(m.fecha) }}
                        @if (m.responsable) { · {{ m.responsable }} }
                        @if (m.firmada === false) {
                          <span class="chip bg-amber-50 text-amber-800 ring-amber-200 ml-1.5">Borrador</span>
                        }
                      </p>
                    </div>
                    <div class="flex gap-1 shrink-0">
                      <button type="button" class="btn-secundario btn-sm" [disabled]="indiceSel() === 0"
                              (click)="indiceSel.set(indiceSel() - 1)" aria-label="Anterior">‹</button>
                      <button type="button" class="btn-secundario btn-sm"
                              [disabled]="indiceSel() >= momentos().length - 1"
                              (click)="indiceSel.set(indiceSel() + 1)" aria-label="Siguiente">›</button>
                    </div>
                  </div>

                  @if (areasCatalogo().length) {
                    <app-mapa-corporal [areas]="areasCatalogo()" [seleccion]="m.areas" modo="lectura" />
                  } @else { <app-cargando /> }

                  <ul class="mt-4 space-y-1.5">
                    @for (a of m.areas; track a.codigo) {
                      <li class="flex items-center gap-2.5 text-sm">
                        <span class="w-3 h-3 rounded-full shrink-0"
                              [style.background]="color(a.nivel_dolor)"></span>
                        <span class="flex-1">{{ a.nombre }}</span>
                        @if (a.movilidad) {
                          <span class="chip-neutro text-[10px]">{{ textoMovilidad(a.movilidad) }}</span>
                        }
                        @if (a.inflamacion) {
                          <span class="chip bg-rose-50 text-rose-800 ring-rose-200 text-[10px]">Inflamación</span>
                        }
                        <span class="font-semibold tabular-nums text-xs">{{ a.nivel_dolor }}/10</span>
                      </li>
                    }
                  </ul>
                }
              </section>

              <!-- Comparación y tendencia -->
              <section class="tarjeta tarjeta-cuerpo">
                <h2 class="font-semibold mb-1">Evolución del dolor</h2>
                <p class="text-sm text-slate-500 mb-4">
                  Por zona, de la primera a la última medición. La barra resaltada es el
                  momento que está viendo.
                </p>

                @if (evolucionPorArea().length === 0) {
                  <app-vacio titulo="Todavía no hay suficientes mediciones" />
                } @else {
                  <div class="space-y-4">
                    @for (a of evolucionPorArea(); track a.codigo) {
                      <div>
                        <div class="flex items-center justify-between text-sm mb-1.5">
                          <span class="font-medium">{{ a.nombre }}</span>
                          <span class="text-xs" [class]="a.mejora > 0 ? 'text-emerald-600'
                                                        : a.mejora < 0 ? 'text-rose-600' : 'text-slate-400'">
                            {{ a.primero }} → {{ a.ultimo }}
                            @if (a.mejora > 0) { <span>({{ a.mejora }} menos)</span> }
                            @if (a.mejora < 0) { <span>({{ -a.mejora }} más)</span> }
                          </span>
                        </div>
                        <div class="flex items-end gap-1 h-14">
                          @for (p of a.puntos; track $index) {
                            <div class="flex-1 rounded-t transition-all min-w-1.5"
                                 [style.height.%]="Math.max(p.nivel_dolor * 10, 6)"
                                 [style.background]="color(p.nivel_dolor)"
                                 [style.opacity]="mismoMomento(p.fecha) ? 1 : 0.4"
                                 [title]="fecha(p.fecha) + ' · ' + p.nivel_dolor + '/10'"></div>
                          }
                        </div>
                      </div>
                    }
                  </div>
                }
              </section>
            </div>
          }
        }

        <!-- ---------- Pagos ---------- -->
        @if (pestana() === 'pagos' && auth.veFinanzas()) {
          <div class="tarjeta overflow-hidden">
            <header class="px-5 py-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="font-semibold">Pagos</h2>
                @if (saldo(); as s) {
                  <p class="text-sm text-slate-500 mt-0.5">
                    Cargos {{ dinero(s.total_cargos) }} · Pagado {{ dinero(s.total_pagado) }} ·
                    <strong [class.text-rose-600]="s.saldo > 0"
                            [class.text-emerald-700]="s.saldo <= 0">
                      Saldo {{ dinero(s.saldo) }}
                    </strong>
                  </p>
                }
              </div>
              <button type="button" class="btn-primario btn-sm" (click)="abrirPago()">
                Registrar pago
              </button>
            </header>

            @if (pagos().length === 0) {
              <app-vacio titulo="Sin pagos registrados"
                         detalle="Los cobros de este paciente aparecerán aquí." />
            } @else {
              <div class="overflow-x-auto">
                <table class="tabla">
                  <thead><tr>
                    <th>Fecha</th><th>Concepto</th><th>Método</th>
                    <th class="text-right">Monto</th><th>Estado</th><th></th>
                  </tr></thead>
                  <tbody>
                    @for (p of pagos(); track p.id) {
                      <tr [class.opacity-50]="p.estado === 'anulado'">
                        <td class="whitespace-nowrap">{{ fecha(p.fecha) }}</td>
                        <td class="text-sm">
                          {{ p.descripcion ?? p.referencia ?? '—' }}
                          @if (p.cita_id) {
                            <span class="block text-xs text-slate-400">
                              {{ codigoDeCita(p.cita_id) }}
                            </span>
                          }
                          @if (p.motivo_anulacion) {
                            <span class="block text-xs text-rose-600">{{ p.motivo_anulacion }}</span>
                          }
                        </td>
                        <td class="text-sm capitalize">{{ p.metodo }}</td>
                        <td class="text-right tabular-nums font-medium">{{ dinero(p.monto) }}</td>
                        <td>
                          <span class="chip" [class]="p.estado === 'pagado'
                            ? 'bg-emerald-50 text-emerald-800 ring-emerald-200'
                            : 'bg-slate-100 text-slate-600 ring-slate-300'">{{ p.estado }}</span>
                        </td>
                        <td class="text-right">
                          @if (p.estado === 'pagado') {
                            <button type="button" class="btn-fantasma btn-sm"
                                    (click)="abrirAnular(p)">Anular</button>
                          }
                        </td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
            }
          </div>
        }

        <!-- ---------- Identidad ---------- -->
        @if (pestana() === 'identidad' && auth.esAdmin()) {
          <div class="space-y-5">
            <section class="tarjeta overflow-hidden">
              <header class="px-5 py-4 border-b border-slate-100">
                <h2 class="font-semibold">Historial de identidad</h2>
                <p class="text-sm text-slate-500 mt-0.5">
                  Correcciones de documento y fusiones. Los valores se guardan enmascarados.
                </p>
              </header>
              @if (historial().length === 0) {
                <app-vacio titulo="Sin cambios de identidad" />
              } @else {
                <table class="tabla">
                  <thead><tr><th>Fecha</th><th>Campo</th><th>Antes</th><th>Después</th>
                    <th>Motivo</th><th>Responsable</th></tr></thead>
                  <tbody>
                    @for (h of historial(); track h.id) {
                      <tr>
                        <td class="whitespace-nowrap text-sm">{{ fechaYHora(h.realizado_en) }}</td>
                        <td class="text-sm">{{ h.campo }}</td>
                        <td class="dpi">{{ h.valor_anterior }}</td>
                        <td class="dpi">{{ h.valor_nuevo }}</td>
                        <td class="text-sm">{{ h.motivo }}</td>
                        <td class="text-sm">{{ h.perfiles?.nombre_completo ?? '—' }}</td>
                      </tr>
                    }
                  </tbody>
                </table>
              }
            </section>
          </div>
        }
      </div>
    }

    <!-- ============ Diálogos ============ -->
    <app-dialogo [(abierto)]="dlgVerDpi" titulo="Ver documento completo"
                 subtitulo="La consulta queda registrada en la bitácora de auditoría">
      <div class="space-y-3">
        <p class="text-sm text-slate-600">
          Indique brevemente por qué necesita el documento completo. Quedará asociado a su usuario.
        </p>
        <input class="campo" placeholder="Ej. verificación de identidad en mostrador"
               [value]="motivoDpi()" (input)="motivoDpi.set($any($event.target).value)">
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgVerDpi.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" (click)="verDpi()">Ver documento</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgEditar" titulo="Editar datos del paciente" ancho="lg">
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="sm:col-span-2">
          <label class="etiqueta" for="e-nom">Nombre completo</label>
          <input id="e-nom" class="campo" [value]="edit()['nombre_completo'] ?? ''"
                 (input)="setEdit('nombre_completo', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="e-tel">Teléfono</label>
          <input id="e-tel" class="campo" [value]="edit()['telefono'] ?? ''"
                 (input)="setEdit('telefono', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="e-wa">WhatsApp</label>
          <input id="e-wa" class="campo" [value]="edit()['whatsapp'] ?? ''"
                 (input)="setEdit('whatsapp', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="e-mail">Correo</label>
          <input id="e-mail" class="campo" type="email" [value]="edit()['email'] ?? ''"
                 (input)="setEdit('email', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="e-nac">Fecha de nacimiento</label>
          <input id="e-nac" class="campo" type="date" [value]="edit()['fecha_nacimiento'] ?? ''"
                 (input)="setEdit('fecha_nacimiento', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="e-fis">Fisioterapeuta principal</label>
          <select id="e-fis" class="campo" [value]="edit()['fisioterapeuta_id'] ?? ''"
                  (change)="setEdit('fisioterapeuta_id', $any($event.target).value)">
            <option value="">Sin asignar</option>
            @for (f of fisios(); track f.id) { <option [value]="f.id">{{ f.nombre_completo }}</option> }
          </select>
        </div>
        <div>
          <label class="etiqueta" for="e-canal">Canal preferido</label>
          <select id="e-canal" class="campo" [value]="edit()['canal_preferido'] ?? 'whatsapp'"
                  (change)="setEdit('canal_preferido', $any($event.target).value)">
            <option value="whatsapp">WhatsApp</option>
            <option value="email">Correo</option>
            <option value="telefono">Teléfono</option>
          </select>
        </div>
        <div class="sm:col-span-2">
          <label class="etiqueta" for="e-dir">Dirección</label>
          <input id="e-dir" class="campo" [value]="edit()['direccion'] ?? ''"
                 (input)="setEdit('direccion', $any($event.target).value)">
        </div>
        <div class="sm:col-span-2">
          <label class="etiqueta" for="e-notas">Notas administrativas</label>
          <textarea id="e-notas" class="campo" rows="2"
                    (input)="setEdit('notas_administrativas', $any($event.target).value)"
          >{{ edit()['notas_administrativas'] ?? '' }}</textarea>
        </div>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgEditar.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="guardando()"
                (click)="guardarEdicion()">Guardar</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgPago" titulo="Registrar pago"
                 [subtitulo]="paciente()?.nombre_completo ?? ''" ancho="lg">
      <div class="space-y-4">
        @if (saldo(); as sal) {
          @if (sal.saldo > 0) {
            <button type="button"
                    class="w-full rounded-lg bg-slate-50 ring-1 ring-slate-200 px-4 py-3
                           text-left hover:bg-slate-100 transition-colors"
                    (click)="pagoMonto.set(sal.saldo)">
              <span class="text-sm text-slate-600">Saldo pendiente</span>
              <span class="float-right font-semibold tabular-nums text-rose-600">
                {{ dinero(sal.saldo) }}
              </span>
              <span class="block text-xs text-slate-400 mt-0.5">Toque para usar este monto</span>
            </button>
          }
        }

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="etiqueta" for="pg-monto">Monto (GTQ)</label>
            <input id="pg-monto" class="campo" type="number" min="0.01" step="0.01"
                   [class.campo-error]="pagoMonto() < 0"
                   [value]="pagoMonto()" (input)="pagoMonto.set(+$any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="pg-met">Método</label>
            <select id="pg-met" class="campo" [value]="pagoMetodo()"
                    (change)="pagoMetodo.set($any($event.target).value)">
              @for (m of metodosPago; track m) { <option [value]="m">{{ m }}</option> }
            </select>
          </div>
          <div class="sm:col-span-2">
            <label class="etiqueta" for="pg-cita">Cita relacionada (opcional)</label>
            <select id="pg-cita" class="campo" [value]="pagoCita()"
                    (change)="pagoCita.set($any($event.target).value)">
              <option value="">Sin ligar a una cita</option>
              @for (c of citasCobrables(); track c.id) {
                <option [value]="c.id">
                  {{ c.inicio_programado ? fecha(c.inicio_programado) : fecha(c.fecha_solicitada + 'T12:00:00') }}
                  — {{ c.codigo_referencia }} ({{ c.estado }})
                </option>
              }
            </select>
            <p class="ayuda">Ligarlo ayuda a saber qué visita se cobró.</p>
          </div>
          <div>
            <label class="etiqueta" for="pg-ref">Referencia / boleta</label>
            <input id="pg-ref" class="campo" [value]="pagoReferencia()"
                   (input)="pagoReferencia.set($any($event.target).value)">
          </div>
          <div>
            <label class="etiqueta" for="pg-desc">Concepto</label>
            <input id="pg-desc" class="campo" placeholder="Ej. sesión de terapia manual"
                   [value]="pagoDescripcion()" (input)="pagoDescripcion.set($any($event.target).value)">
          </div>
        </div>

        <p class="rounded-lg bg-slate-50 ring-1 ring-slate-200 px-3 py-2.5 text-xs text-slate-600">
          Un pago aplicado no se edita: si se equivoca, se anula y se registra otro.
          Queda el rastro de ambos.
        </p>

        @if (errorPago()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorPago() }}
          </p>
        }
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgPago.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="pagoMonto() <= 0 || guardando()"
                (click)="guardarPago()">
          {{ guardando() ? 'Registrando…' : 'Registrar pago' }}
        </button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgAnular" titulo="Anular pago"
                 subtitulo="El movimiento queda visible, marcado como anulado">
      <div>
        <label class="etiqueta" for="pg-anu">Motivo</label>
        <textarea id="pg-anu" class="campo" rows="3"
                  (input)="motivoAnulacion.set($any($event.target).value)"
        >{{ motivoAnulacion() }}</textarea>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgAnular.set(false)">Volver</button>
        <button type="button" class="btn-peligro"
                [disabled]="motivoAnulacion().trim().length < 3 || guardando()"
                (click)="anularPago()">Anular</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgDpi" titulo="Corregir documento"
                 subtitulo="Se conserva el historial; el cambio queda auditado">
      <div class="space-y-4">
        <div>
          <label class="etiqueta" for="c-dpi">Nuevo DPI</label>
          <input id="c-dpi" class="campo font-mono" inputmode="numeric" placeholder="0000 00000 0000"
                 [class.campo-error]="nuevoDpi() !== '' && !nuevoDpiOk()"
                 [value]="nuevoDpi()" (input)="escribirNuevoDpi($event)">
          @if (nuevoDpi() !== '' && !nuevoDpiOk()) {
            <p class="error-texto">{{ errorNuevoDpi() }}</p>
          }
        </div>
        <div>
          <label class="etiqueta" for="c-mot">Motivo de la corrección</label>
          <textarea id="c-mot" class="campo" rows="2"
                    placeholder="Ej. el paciente presentó su DPI físico y no coincidía"
                    (input)="motivoCorreccion.set($any($event.target).value)"
          >{{ motivoCorreccion() }}</textarea>
        </div>
        @if (errorCorreccion()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorCorreccion() }}
            @if (choque()) {
              <a [routerLink]="['/panel/pacientes', choque()]" class="underline ml-1"
                 (click)="dlgDpi.set(false)">Ver la otra ficha</a>
            }
          </p>
        }
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgDpi.set(false)">Cancelar</button>
        <button type="button" class="btn-primario"
                [disabled]="!nuevoDpiOk() || motivoCorreccion().trim().length < 5 || guardando()"
                (click)="guardarCorreccion()">Corregir</button>
      </div>
    </app-dialogo>
  `,
})
export class FichaPaciente {
  private readonly pacientes = inject(PacientesService);
  private readonly citas = inject(CitasService);
  private readonly clinica = inject(ClinicaService);
  private readonly catalogos = inject(CatalogosService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly id = input.required<string>();

  readonly Math = Math;
  readonly cargando = signal(true);
  readonly pestana = signal<Pestana>('resumen');
  readonly paciente = signal<PacienteListado | null>(null);
  readonly alertas = signal<Alerta[]>([]);
  readonly citasLista = signal<CitaListado[]>([]);
  readonly sesiones = signal<SesionDetalle[]>([]);
  readonly pagos = signal<Pago[]>([]);
  readonly saldo = signal<{ total_cargos: number; total_pagado: number; saldo: number } | null>(null);
  readonly evolucion = signal<PuntoEvolucion[]>([]);
  readonly momentos = signal<MomentoMapa[]>([]);
  readonly indiceSel = signal(0);
  readonly historial = signal<any[]>([]);
  readonly clinico = signal<Record<string, string | undefined>>({});
  readonly fisios = signal<Perfil[]>([]);
  readonly areasCatalogo = this.catalogos.areas;

  readonly dpiVisible = signal<string | null>(null);
  readonly motivoDpi = signal('');
  readonly dlgVerDpi = signal(false);
  readonly dlgEditar = signal(false);
  readonly dlgDpi = signal(false);
  readonly guardando = signal(false);

  // --- Pagos --------------------------------------------------------------
  readonly metodosPago: MetodoPago[] =
    ['efectivo', 'tarjeta', 'transferencia', 'deposito', 'otro'];
  readonly dlgPago = signal(false);
  readonly dlgAnular = signal(false);
  readonly pagoMonto = signal(0);
  readonly pagoMetodo = signal<MetodoPago>('efectivo');
  readonly pagoCita = signal('');
  readonly pagoReferencia = signal('');
  readonly pagoDescripcion = signal('');
  readonly errorPago = signal('');
  readonly pagoAnular = signal<Pago | null>(null);
  readonly motivoAnulacion = signal('');
  readonly edit = signal<Record<string, string | undefined>>({});
  readonly nuevoDpi = signal('');
  readonly motivoCorreccion = signal('');
  readonly errorCorreccion = signal('');
  readonly choque = signal<string | null>(null);

  readonly camposClinicos = [
    { campo: 'antecedentes', etiqueta: 'Antecedentes', ancho: true },
    { campo: 'alergias', etiqueta: 'Alergias', ancho: false },
    { campo: 'medicamentos', etiqueta: 'Medicamentos', ancho: false },
    { campo: 'cirugias_previas', etiqueta: 'Cirugías previas', ancho: false },
    { campo: 'observaciones', etiqueta: 'Observaciones generales', ancho: false },
  ];

  readonly fecha = fechaCorta;
  readonly fechaYHora = fechaHora;
  readonly hora = horaCorta;
  readonly tel = formatearTelefono;
  readonly cuando = haceCuanto;
  readonly color = colorDolor;
  readonly dinero = moneda;

  readonly ini = computed(() => iniciales(this.paciente()?.nombre_completo));
  readonly puedeVerDpi = computed(() => this.auth.esAdmin() || this.auth.esFisio());

  /** Solo tiene sentido cobrar visitas que ocurrieron o están agendadas. */
  readonly citasCobrables = computed(() =>
    this.citasLista().filter((c) => ['atendida', 'confirmada'].includes(c.estado)));

  codigoDeCita(id: string): string {
    return this.citasLista().find((c) => c.id === id)?.codigo_referencia ?? '';
  }

  abrirPago() {
    const s = this.saldo();
    this.pagoMonto.set(s && s.saldo > 0 ? Number(s.saldo) : 0);
    this.pagoMetodo.set('efectivo');
    // Se propone la última visita ATENDIDA: es lo que normalmente se cobra,
    // no la cita futura que casualmente es la más reciente de la lista.
    const cobrables = this.citasCobrables();
    this.pagoCita.set(
      (cobrables.find((c) => c.estado === 'atendida') ?? cobrables[0])?.id ?? '');
    this.pagoReferencia.set('');
    this.pagoDescripcion.set('');
    this.errorPago.set('');
    this.dlgPago.set(true);
  }

  async guardarPago() {
    if (this.pagoMonto() <= 0) return;
    this.guardando.set(true);
    this.errorPago.set('');
    try {
      await this.clinica.registrarPago({
        paciente_id: this.id(),
        cita_id: this.pagoCita() || null,
        monto: this.pagoMonto(),
        metodo: this.pagoMetodo(),
        estado: 'pagado',
        referencia: this.pagoReferencia() || null,
        descripcion: this.pagoDescripcion() || null,
        registrado_por: this.auth.perfil()!.id,
      });
      this.avisos.exito(`Pago de ${moneda(this.pagoMonto())} registrado.`);
      this.dlgPago.set(false);
      await this.cargar();
    } catch (e) {
      this.errorPago.set(
        e instanceof Error && /insufficient|permission/i.test(e.message)
          ? 'Su rol no permite registrar pagos.'
          : 'No se pudo registrar el pago.',
      );
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

  async anularPago() {
    const p = this.pagoAnular();
    if (!p || this.motivoAnulacion().trim().length < 3) return;
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

  readonly nuevoDpiOk = computed(() => validarDpi(this.nuevoDpi()).valido);
  readonly errorNuevoDpi = computed(() => validarDpi(this.nuevoDpi()).mensaje ?? '');

  readonly pestanasVisibles = computed(() => {
    const p: Array<{ id: Pestana; etiqueta: string }> = [
      { id: 'resumen', etiqueta: 'Resumen' },
      { id: 'citas', etiqueta: 'Citas' },
    ];
    if (this.auth.veClinico()) p.push({ id: 'clinico', etiqueta: 'Historial clínico' });
    p.push({ id: 'evolucion', etiqueta: 'Evolución' });
    if (this.auth.veFinanzas()) p.push({ id: 'pagos', etiqueta: 'Pagos' });
    if (this.auth.esAdmin()) p.push({ id: 'identidad', etiqueta: 'Identidad' });
    return p;
  });

  readonly datosContacto = computed(() => {
    const p = this.paciente();
    if (!p) return [];
    return [
      { k: 'Documento', v: this.dpiVisible() ?? p.dpi_mascara },
      { k: 'Teléfono', v: formatearTelefono(p.telefono) || '—' },
      { k: 'WhatsApp', v: formatearTelefono(p.whatsapp) || '—' },
      { k: 'Correo', v: p.email ?? '—' },
      { k: 'Canal preferido', v: p.canal_preferido },
      { k: 'Nacimiento', v: p.fecha_nacimiento ? fechaCorta(p.fecha_nacimiento + 'T12:00:00') : '—' },
      { k: 'Fisioterapeuta', v: p.fisioterapeuta ?? 'Sin asignar' },
      { k: 'Estado', v: p.estado },
    ];
  });

  readonly momentoSel = computed(() => this.momentos()[this.indiceSel()] ?? null);

  numeroSesion(indice: number): number {
    return this.momentos().slice(0, indice + 1)
      .filter((m) => m.momento_tipo === 'sesion').length;
  }

  /** Resalta en las barras el momento que se está viendo. */
  mismoMomento(fecha: string): boolean {
    return this.momentoSel()?.fecha === fecha;
  }

  textoMovilidad(m: string | null | undefined): string {
    return { normal: 'Movilidad normal', limitada: 'Limitada', muy_limitada: 'Muy limitada' }[m ?? ''] ?? '';
  }

  readonly evolucionPorArea = computed(() => {
    const grupos = new Map<string, PuntoEvolucion[]>();
    for (const p of this.evolucion()) {
      grupos.set(p.area_codigo, [...(grupos.get(p.area_codigo) ?? []), p]);
    }
    return [...grupos.entries()].map(([codigo, puntos]) => {
      const orden = [...puntos].sort((a, b) => a.fecha.localeCompare(b.fecha));
      const primero = orden[0].nivel_dolor;
      const ultimo = orden[orden.length - 1].nivel_dolor;
      return {
        codigo,
        nombre: orden[0].area_nombre,
        puntos: orden,
        primero,
        ultimo,
        mejora: primero - ultimo,
      };
    }).sort((a, b) => b.ultimo - a.ultimo);
  });

  constructor() {
    void this.catalogos.cargarAreas();
    void this.catalogos.fisioterapeutas().then((f) => this.fisios.set(f));
    queueMicrotask(() => void this.cargar());
  }

  private async cargar() {
    this.cargando.set(true);
    const id = this.id();
    try {
      const p = await this.pacientes.obtener(id);
      this.paciente.set(p);
      if (!p) return;

      const tareas: Array<Promise<unknown>> = [
        this.pacientes.alertasDePaciente(id).then((a) => this.alertas.set(a.filter((x) => x.estado === 'pendiente'))),
        this.citas.listar({ pacienteId: id, limite: 100 }).then((c) => this.citasLista.set(c.reverse())),
        this.pacientes.evolucion(id).then((e) => this.evolucion.set(e)),
        this.pacientes.historialMapa(id).then((m) => {
          this.momentos.set(m);
          this.indiceSel.set(Math.max(m.length - 1, 0));   // arranca en el actual
        }),
      ];
      if (this.auth.veClinico()) {
        tareas.push(this.clinica.sesionesDePaciente(id).then((s) => this.sesiones.set(s)));
        tareas.push(this.pacientes.datosClinicos(id).then((c) => this.clinico.set((c ?? {}) as Record<string, string | undefined>)));
      }
      if (this.auth.veFinanzas()) {
        tareas.push(this.clinica.pagos({ pacienteId: id }).then((p2) => this.pagos.set(p2)));
        tareas.push(this.pacientes.saldo(id).then((s) => this.saldo.set(s)));
      }
      if (this.auth.esAdmin()) {
        tareas.push(this.pacientes.historialIdentidad(id).then((h) => this.historial.set(h)));
      }
      await Promise.allSettled(tareas);
    } catch (e) {
      this.avisos.error('No se pudo cargar la ficha.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  objeto(d: Record<string, unknown>): Array<{ k: string; v: string }> {
    return Object.entries(d ?? {}).map(([k, v]) => ({ k: k.replace(/_/g, ' '), v: String(v) }));
  }

  etiquetaAlerta(t: Alerta['tipo']): string { return ETIQUETAS_ALERTA[t] ?? t; }

  // --- DPI ----------------------------------------------------------------

  abrirVerDpi() { this.motivoDpi.set(''); this.dlgVerDpi.set(true); }
  ocultarDpi() { this.dpiVisible.set(null); }

  async verDpi() {
    try {
      const r = await this.pacientes.verDpi(this.id(), this.motivoDpi());
      this.dpiVisible.set(formatearDpi(r.documento));
      this.dlgVerDpi.set(false);
      this.avisos.info('La consulta quedó registrada en la auditoría.');
    } catch {
      this.avisos.error('Su rol no permite ver el documento completo.');
      this.dlgVerDpi.set(false);
    }
  }

  abrirCorregirDpi() {
    this.nuevoDpi.set('');
    this.motivoCorreccion.set('');
    this.errorCorreccion.set('');
    this.choque.set(null);
    this.dlgDpi.set(true);
  }

  escribirNuevoDpi(e: Event) {
    this.nuevoDpi.set(formatearDpi((e.target as HTMLInputElement).value));
  }

  async guardarCorreccion() {
    this.guardando.set(true);
    this.errorCorreccion.set('');
    this.choque.set(null);
    try {
      const r = await this.pacientes.corregirDpi(
        this.id(), this.nuevoDpi().replace(/\D/g, ''), this.motivoCorreccion(),
      );
      if (!r.ok) {
        this.errorCorreccion.set(r.mensaje ?? 'No se pudo corregir el documento.');
        this.choque.set(r.paciente_id ?? null);
        return;
      }
      this.avisos.exito('Documento corregido.');
      this.dlgDpi.set(false);
      this.dpiVisible.set(null);
      await this.cargar();
    } catch {
      this.errorCorreccion.set('No se pudo corregir el documento.');
    } finally {
      this.guardando.set(false);
    }
  }

  // --- Edición ------------------------------------------------------------

  abrirEditar() {
    const p = this.paciente()!;
    this.edit.set({
      nombre_completo: p.nombre_completo,
      telefono: p.telefono ?? '',
      whatsapp: p.whatsapp ?? '',
      email: p.email ?? '',
      fecha_nacimiento: p.fecha_nacimiento ?? '',
      fisioterapeuta_id: p.fisioterapeuta_id ?? '',
      canal_preferido: p.canal_preferido,
      direccion: '',
      notas_administrativas: '',
    });
    this.dlgEditar.set(true);
  }

  setEdit(campo: string, valor: string) {
    this.edit.update((e) => ({ ...e, [campo]: valor }));
  }

  async guardarEdicion() {
    this.guardando.set(true);
    try {
      const e = this.edit();
      await this.pacientes.actualizar(this.id(), {
        nombre_completo: e['nombre_completo'],
        telefono: e['telefono'] || null,
        whatsapp: e['whatsapp'] || null,
        email: e['email'] || null,
        fecha_nacimiento: e['fecha_nacimiento'] || null,
        fisioterapeuta_id: e['fisioterapeuta_id'] || null,
        canal_preferido: e['canal_preferido'],
        direccion: e['direccion'] || null,
        notas_administrativas: e['notas_administrativas'] || null,
      });
      this.avisos.exito('Datos actualizados.');
      this.dlgEditar.set(false);
      await this.cargar();
    } catch (err) {
      this.avisos.error('No se pudieron guardar los cambios.');
      console.error(err);
    } finally {
      this.guardando.set(false);
    }
  }

  // --- Clínico ------------------------------------------------------------

  setClinico(campo: string, valor: string) {
    this.clinico.update((c) => ({ ...c, [campo]: valor }));
  }

  async guardarClinico() {
    this.guardando.set(true);
    try {
      const c = this.clinico();
      await this.pacientes.guardarDatosClinicos(this.id(), {
        antecedentes: c['antecedentes'] || null,
        alergias: c['alergias'] || null,
        medicamentos: c['medicamentos'] || null,
        cirugias_previas: c['cirugias_previas'] || null,
        observaciones: c['observaciones'] || null,
        actualizado_por: this.auth.perfil()!.id,
      });
      this.avisos.exito('Antecedentes guardados.');
    } catch {
      this.avisos.error('No se pudieron guardar los antecedentes.');
    } finally {
      this.guardando.set(false);
    }
  }

  async resolverAlerta(a: Alerta) {
    try {
      await this.pacientes.resolverAlerta(a.id, 'revisada');
      this.alertas.update((l) => l.filter((x) => x.id !== a.id));
    } catch {
      this.avisos.error('No se pudo actualizar la alerta.');
    }
  }

  imprimir() { window.print(); }
}
