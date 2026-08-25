import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { CatalogosService } from '../core/api/catalogos.service';
import { PacientesService } from '../core/api/pacientes.service';
import { SupabaseService } from '../core/supabase.service';
import {
  Duplicado, ETIQUETAS_ROL, Perfil, RegistroAuditoria, RolUsuario, Tratamiento,
} from '../core/modelos';
import { AvisosService } from '../core/util/avisos.service';
import { fechaCorta, fechaHora, moneda } from '../core/util/formato';
import { Cargando, Dialogo, Vacio } from '../shared/ui';

type Seccion = 'duplicados' | 'usuarios' | 'tratamientos' | 'horarios' | 'auditoria' | 'ajustes';

const DIAS = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

@Component({
  selector: 'app-administracion',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Dialogo, Cargando, Vacio],
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
      <header class="mb-5">
        <h1 class="text-2xl font-bold tracking-tight">Administración</h1>
        <p class="text-sm text-slate-500 mt-0.5">Catálogos, personal, duplicados y bitácora.</p>
      </header>

      <div class="flex gap-1 p-1 bg-slate-100 rounded-lg w-fit mb-5 overflow-x-auto">
        @for (s of secciones; track s.id) {
          <button type="button" class="px-4 py-1.5 text-sm rounded-md whitespace-nowrap transition-colors"
                  [class]="seccion() === s.id ? 'bg-white shadow-sm font-medium' : 'text-slate-500'"
                  (click)="cambiar(s.id)">
            {{ s.etiqueta }}
            @if (s.id === 'duplicados' && duplicados().length) {
              <span class="ml-1.5 text-xs font-semibold text-marca-700">{{ duplicados().length }}</span>
            }
          </button>
        }
      </div>

      @if (cargando()) { <app-cargando /> }

      <!-- ---------- Duplicados ---------- -->
      @if (seccion() === 'duplicados' && !cargando()) {
        @if (duplicados().length === 0) {
          <div class="tarjeta">
            <app-vacio titulo="No hay duplicados pendientes"
                       detalle="El sistema compara nombre, teléfono y correo al crear cada ficha." />
          </div>
        } @else {
          <div class="space-y-4">
            @for (d of duplicados(); track d.id) {
              <article class="tarjeta tarjeta-cuerpo">
                <div class="flex items-center justify-between gap-3 mb-4">
                  <div>
                    <p class="font-semibold">Posible duplicado</p>
                    <p class="text-xs text-slate-500">
                      {{ motivoTexto(d.motivo) }} · coincidencia {{ (d.puntaje * 100).toFixed(0) }}%
                    </p>
                  </div>
                  <button type="button" class="btn-fantasma btn-sm" (click)="descartar(d)">
                    No son la misma persona
                  </button>
                </div>

                <div class="grid gap-4 sm:grid-cols-2">
                  @for (lado of [ladoA(d), ladoB(d)]; track lado.id) {
                    <div class="rounded-lg ring-1 p-4"
                         [class]="conservar()[d.id] === lado.id ? 'ring-marca-500 bg-marca-50' : 'ring-slate-200'">
                      <p class="font-medium">{{ lado.nombre }}</p>
                      <dl class="mt-2 space-y-1 text-sm text-slate-600">
                        <div class="flex gap-2"><dt class="text-slate-400">DPI</dt><dd class="dpi">{{ lado.dpi }}</dd></div>
                        <div class="flex gap-2"><dt class="text-slate-400">Tel.</dt><dd>{{ lado.telefono ?? '—' }}</dd></div>
                        <div class="flex gap-2"><dt class="text-slate-400">Correo</dt><dd class="truncate">{{ lado.email ?? '—' }}</dd></div>
                        <div class="flex gap-2"><dt class="text-slate-400">Citas</dt><dd>{{ lado.citas }}</dd></div>
                        <div class="flex gap-2"><dt class="text-slate-400">Creada</dt><dd>{{ fecha(lado.creado) }}</dd></div>
                      </dl>
                      <div class="mt-3 flex gap-2">
                        <button type="button" class="btn-secundario btn-sm flex-1"
                                (click)="elegirConservar(d.id, lado.id)">
                          {{ conservar()[d.id] === lado.id ? '✓ Se conserva' : 'Conservar esta' }}
                        </button>
                        <a [routerLink]="['/panel/pacientes', lado.id]" class="btn-fantasma btn-sm">Ver</a>
                      </div>
                    </div>
                  }
                </div>

                @if (conservar()[d.id]) {
                  <div class="mt-4 pt-4 border-t border-slate-100">
                    <label class="etiqueta" [attr.for]="'m-' + d.id">Motivo de la fusión</label>
                    <div class="flex gap-2">
                      <input [id]="'m-' + d.id" class="campo"
                             placeholder="Ej. DPI mal digitado en la segunda solicitud"
                             [value]="motivos()[d.id] ?? ''"
                             (input)="setMotivo(d.id, $any($event.target).value)">
                      <button type="button" class="btn-primario shrink-0"
                              [disabled]="(motivos()[d.id] ?? '').trim().length < 5 || guardando()"
                              (click)="fusionar(d)">Fusionar</button>
                    </div>
                    <p class="ayuda">
                      Todo el historial (citas, sesiones, pagos, mensajes) pasa a la ficha que se conserva.
                      La otra queda marcada como fusionada, no se borra.
                    </p>
                  </div>
                }
              </article>
            }
          </div>
        }
      }

      <!-- ---------- Usuarios ---------- -->
      @if (seccion() === 'usuarios' && !cargando()) {
        <div class="tarjeta overflow-hidden">
          <header class="px-5 py-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 class="font-semibold">Personal de la clínica</h2>
              <p class="text-sm text-slate-500 mt-0.5">
                Los únicos usuarios con sesión. Los pacientes no aparecen aquí.
              </p>
            </div>
            @if (auth.esSuperadmin()) {
              <button type="button" class="btn-primario btn-sm" (click)="abrirNuevoUsuario()">
                Crear usuario
              </button>
            }
          </header>
          <table class="tabla">
            <thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th>Atiende</th><th>Colegiado</th><th>Estado</th><th></th></tr></thead>
            <tbody>
              @for (p of personal(); track p.id) {
                <tr>
                  <td>
                    <span class="font-medium">{{ p.nombre_completo }}</span>
                    @if (p.atiende) {
                      <span class="inline-block w-2.5 h-2.5 rounded-full ml-2 align-middle"
                            title="Color en la agenda"
                            [style.background]="p.color_agenda"></span>
                    }
                  </td>
                  <td class="text-sm text-slate-600">{{ p.email }}</td>
                  <td>
                    @if (auth.esSuperadmin() && p.id !== auth.perfil()?.id) {
                      <select class="campo py-1 text-xs w-44" [value]="p.rol"
                              (change)="cambiarRol(p, $any($event.target).value)">
                        @for (r of roles; track r) { <option [value]="r">{{ etiquetaRol(r) }}</option> }
                      </select>
                    } @else {
                      <span class="chip-neutro">{{ etiquetaRol(p.rol) }}</span>
                    }
                  </td>
                  <td>
                    @if (auth.esSuperadmin() && p.rol !== 'fisioterapeuta' && p.rol !== 'recepcion') {
                      <label class="inline-flex items-center gap-2 text-sm cursor-pointer">
                        <input type="checkbox" class="w-4 h-4 accent-teal-700"
                               [attr.id]="'at-' + p.id"
                               [checked]="p.atiende"
                               (change)="alternarAtiende(p, $any($event.target).checked)">
                        <span class="text-slate-600">{{ p.atiende ? 'Sí' : 'No' }}</span>
                      </label>
                    } @else {
                      <span class="text-sm" [class]="p.atiende ? 'text-slate-700' : 'text-slate-400'">
                        {{ p.atiende ? 'Sí' : 'No' }}
                      </span>
                    }
                  </td>
                  <td class="text-sm">{{ p.colegiado ?? '—' }}</td>
                  <td>
                    <span class="chip" [class]="p.activo
                      ? 'bg-emerald-50 text-emerald-800 ring-emerald-200'
                      : 'bg-slate-100 text-slate-600 ring-slate-300'">
                      {{ p.activo ? 'Activo' : 'Inactivo' }}
                    </span>
                  </td>
                  <td class="text-right whitespace-nowrap">
                    @if (auth.esSuperadmin() && p.id !== auth.perfil()?.id) {
                      <button type="button" class="btn-fantasma btn-sm" (click)="abrirClave(p)">
                        Contraseña
                      </button>
                      <button type="button" class="btn-fantasma btn-sm" (click)="alternarActivo(p)">
                        {{ p.activo ? 'Desactivar' : 'Activar' }}
                      </button>
                    }
                  </td>
                </tr>
              }
            </tbody>
          </table>
          <p class="px-5 py-3 text-xs text-slate-500 bg-slate-50 border-t border-slate-100">
            El usuario queda con el correo confirmado y puede entrar de inmediato: lo dio de alta
            un superadministrador, no es un auto-registro que haya que verificar.
            <br>
            <strong>Atiende</strong> es independiente del rol: quien la tiene marcada aparece en la
            agenda, se le pueden asignar citas y firma notas clínicas. El fisioterapeuta la tiene
            siempre; recepción nunca, porque no ve información clínica.
          </p>
        </div>
      }

      <!-- ---------- Tratamientos ---------- -->
      @if (seccion() === 'tratamientos' && !cargando()) {
        <div class="tarjeta overflow-hidden">
          <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
            <div>
              <h2 class="font-semibold">Catálogo de tratamientos</h2>
              <p class="text-sm text-slate-500 mt-0.5">
                Sin precio: el monto se escribe al aplicarlo en la sesión, porque varía por caso.
              </p>
            </div>
            <button type="button" class="btn-secundario btn-sm" (click)="abrirTratamiento(null)">Nuevo</button>
          </header>
          <table class="tabla">
            <thead><tr><th>Código</th><th>Nombre</th><th class="text-right">Duración</th>
              <th>Nota obligatoria</th><th>Estado</th><th></th></tr></thead>
            <tbody>
              @for (t of tratamientos(); track t.id) {
                <tr [class.opacity-50]="!t.activo">
                  <td class="font-mono text-xs">{{ t.codigo }}</td>
                  <td>
                    <span class="font-medium text-sm">{{ t.nombre }}</span>
                    @if (t.descripcion) { <p class="text-xs text-slate-500">{{ t.descripcion }}</p> }
                  </td>
                  <td class="text-right tabular-nums">{{ t.duracion_min }} min</td>
                  <td class="text-sm text-slate-500">{{ t.requiere_nota ? 'Sí' : '—' }}</td>
                  <td><span class="chip-neutro">{{ t.activo ? 'Activo' : 'Inactivo' }}</span></td>
                  <td class="text-right">
                    <button type="button" class="btn-fantasma btn-sm"
                            (click)="abrirTratamiento(t)">Editar</button>
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }

      <!-- ---------- Horarios ---------- -->
      @if (seccion() === 'horarios' && !cargando()) {
        <div class="tarjeta overflow-hidden">
          <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
            <h2 class="font-semibold">Horarios de atención</h2>
            <button type="button" class="btn-secundario btn-sm" (click)="dlgHorario.set(true)">Agregar</button>
          </header>
          @if (horarios().length === 0) {
            <app-vacio titulo="Sin horarios configurados"
                       detalle="Sin horarios, el formulario público no ofrece horas disponibles." />
          } @else {
            <table class="tabla">
              <thead><tr><th>Día</th><th>Horario</th><th>Fisioterapeuta</th>
                <th class="text-right">Cupos</th><th></th></tr></thead>
              <tbody>
                @for (h of horarios(); track h.id) {
                  <tr>
                    <td class="font-medium">{{ dia(h.dia_semana) }}</td>
                    <td class="tabular-nums">{{ h.hora_inicio.slice(0,5) }} — {{ h.hora_fin.slice(0,5) }}</td>
                    <td class="text-sm">{{ h.perfiles?.nombre_completo ?? 'Toda la clínica' }}</td>
                    <td class="text-right tabular-nums">{{ h.cupos }}</td>
                    <td class="text-right">
                      <button type="button" class="btn-fantasma btn-sm"
                              (click)="borrarHorario(h.id)">Eliminar</button>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          }
        </div>
      }

      <!-- ---------- Auditoría ---------- -->
      @if (seccion() === 'auditoria' && !cargando()) {
        <div class="tarjeta overflow-hidden">
          <header class="px-5 py-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 class="font-semibold">Bitácora de auditoría</h2>
              <p class="text-sm text-slate-500 mt-0.5">Inmutable: no se puede editar ni borrar.</p>
            </div>
            <select class="campo w-52 py-2" [value]="filtroAccion()"
                    (change)="filtrarAuditoria($event)">
              <option value="">Todas las acciones</option>
              <option value="consultar_sensible">Consultas de DPI completo</option>
              <option value="fusionar">Fusiones de fichas</option>
              <option value="corregir_dpi">Correcciones de DPI</option>
              <option value="cambiar_rol">Cambios de rol</option>
              <option value="acceso_publico">Accesos públicos</option>
            </select>
          </header>
          @if (auditoria().length === 0) {
            <app-vacio titulo="Sin registros" />
          } @else {
            <div class="overflow-x-auto">
              <table class="tabla">
                <thead><tr><th>Cuándo</th><th>Quién</th><th>Acción</th><th>Entidad</th>
                  <th>Descripción</th><th>IP</th></tr></thead>
                <tbody>
                  @for (r of auditoria(); track r.id) {
                    <tr>
                      <td class="whitespace-nowrap text-xs">{{ fechaYHora(r.ocurrido_en) }}</td>
                      <td class="text-sm">
                        {{ r.actor_email ?? 'sistema / público' }}
                        @if (r.actor_rol) { <span class="text-xs text-slate-400 block">{{ etiquetaRol(r.actor_rol) }}</span> }
                      </td>
                      <td>
                        <span class="chip" [class]="r.accion === 'consultar_sensible'
                          ? 'bg-amber-50 text-amber-800 ring-amber-200'
                          : 'bg-slate-100 text-slate-600 ring-slate-300'">{{ r.accion }}</span>
                      </td>
                      <td class="text-sm">{{ r.entidad }}</td>
                      <td class="text-sm max-w-md truncate" [title]="r.descripcion ?? ''">
                        {{ r.descripcion ?? '—' }}
                      </td>
                      <td class="text-xs text-slate-400 font-mono">{{ r.ip ?? '—' }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }
        </div>
      }

      <!-- ---------- Ajustes ---------- -->
      @if (seccion() === 'ajustes' && !cargando()) {
        <div class="tarjeta tarjeta-cuerpo max-w-2xl">
          <h2 class="font-semibold mb-1">Configuración de la clínica</h2>
          <p class="text-sm text-slate-500 mb-5">
            Estos valores los usa tanto el formulario público como el panel.
          </p>
          <div class="space-y-4">
            @for (c of ajustes; track c.clave) {
              <div>
                <label class="etiqueta" [attr.for]="c.clave">{{ c.etiqueta }}</label>
                <input [id]="c.clave" class="campo" [type]="c.tipo"
                       [value]="valorConfig(c.clave)"
                       (input)="setConfig(c.clave, $any($event.target).value, c.tipo)">
                <p class="ayuda">{{ c.ayuda }}</p>
              </div>
            }
          </div>
          <div class="mt-6 flex justify-end">
            <button type="button" class="btn-primario" [disabled]="guardando()"
                    (click)="guardarAjustes()">Guardar</button>
          </div>

          <div class="mt-8 pt-6 border-t border-slate-200">
            <p class="text-sm font-medium text-slate-700">Notificaciones</p>
            <p class="mt-1 text-sm text-slate-500">
              El envío automático de correo y WhatsApp está <strong>desactivado</strong>. Los
              mensajes se generan y se guardan en la bandeja de salida; mientras tanto, use el
              botón «Copiar enlaces» en cada cita para pegarlos manualmente.
            </p>
          </div>
        </div>
      }
    </div>

    <!-- ============ Crear usuario ============ -->
    <app-dialogo [(abierto)]="dlgUsuario" titulo="Crear usuario del personal"
                 subtitulo="Queda listo para entrar, sin correo de confirmación" ancho="lg">
      <div class="space-y-4">
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="sm:col-span-2">
            <label class="etiqueta" for="u-nom">Nombre completo</label>
            <input id="u-nom" class="campo" autocomplete="off" placeholder="Nombre y apellido"
                   [value]="uNombre()" (input)="uNombre.set($any($event.target).value)">
          </div>

          <div>
            <label class="etiqueta" for="u-mail">Correo</label>
            <input id="u-mail" class="campo" type="email" autocomplete="off"
                   [class.campo-error]="uEmail() !== '' && !uEmailOk()"
                   [value]="uEmail()" (input)="uEmail.set($any($event.target).value)">
            @if (uEmail() !== '' && !uEmailOk()) {
              <p class="error-texto">Revise el formato del correo.</p>
            }
          </div>

          <div>
            <label class="etiqueta" for="u-rol">Rol</label>
            <select id="u-rol" class="campo" [value]="uRol()"
                    (change)="cambiarRolNuevo($any($event.target).value)">
              @for (r of roles; track r) { <option [value]="r">{{ etiquetaRol(r) }}</option> }
            </select>
            <p class="ayuda">{{ descripcionRol() }}</p>
          </div>

          <div>
            <label class="etiqueta" for="u-cl1">Contraseña</label>
            <div class="flex gap-2">
              <input id="u-cl1" class="campo" [type]="verClave() ? 'text' : 'password'"
                     autocomplete="new-password"
                     [class.campo-error]="uClave() !== '' && uClave().length < 10"
                     [value]="uClave()" (input)="uClave.set($any($event.target).value)">
              <button type="button" class="btn-secundario btn-sm shrink-0"
                      (click)="verClave.set(!verClave())">{{ verClave() ? 'Ocultar' : 'Ver' }}</button>
            </div>
            <p class="ayuda">Mínimo 10 caracteres.</p>
          </div>

          <div>
            <label class="etiqueta" for="u-cl2">Repetir contraseña</label>
            <input id="u-cl2" class="campo" [type]="verClave() ? 'text' : 'password'"
                   autocomplete="new-password"
                   [class.campo-error]="uClave2() !== '' && uClave() !== uClave2()"
                   [value]="uClave2()" (input)="uClave2.set($any($event.target).value)">
            @if (uClave2() !== '' && uClave() !== uClave2()) {
              <p class="error-texto">No coinciden.</p>
            }
          </div>

          <div>
            <label class="etiqueta" for="u-tel">Teléfono</label>
            <input id="u-tel" class="campo" [value]="uTelefono()"
                   (input)="uTelefono.set($any($event.target).value)">
          </div>

          @if (uRol() !== 'recepcion') {
            <div class="sm:col-span-2">
              <label class="flex items-start gap-3 rounded-lg ring-1 ring-slate-200 px-3 py-2.5 cursor-pointer"
                     [class]="uAtiende() ? 'bg-teal-50 ring-teal-200' : 'bg-white'">
                <input id="u-atiende" type="checkbox" class="w-4 h-4 mt-0.5 accent-teal-700"
                       [checked]="uAtiende()"
                       [disabled]="uRol() === 'fisioterapeuta'"
                       (change)="uAtiende.set($any($event.target).checked)">
                <span class="text-sm">
                  <strong>Atiende pacientes</strong>
                  <span class="block text-slate-600 mt-0.5">
                    @if (uRol() === 'fisioterapeuta') {
                      Un fisioterapeuta siempre atiende.
                    } @else {
                      Aparece en la agenda, se le pueden asignar citas y firma notas clínicas,
                      además de sus permisos de administración.
                    }
                  </span>
                </span>
              </label>
            </div>
          }

          @if (uAtiende()) {
            <div>
              <label class="etiqueta" for="u-col">Colegiado</label>
              <input id="u-col" class="campo" [value]="uColegiado()"
                     (input)="uColegiado.set($any($event.target).value)">
            </div>
            <div>
              <label class="etiqueta" for="u-esp">Especialidad</label>
              <input id="u-esp" class="campo" placeholder="Ej. deportiva, neurológica"
                     [value]="uEspecialidad()" (input)="uEspecialidad.set($any($event.target).value)">
            </div>
            <div>
              <span class="etiqueta">Color en la agenda</span>
              <div class="flex flex-wrap gap-2">
                @for (c of colores; track c) {
                  <button type="button" class="w-8 h-8 rounded-full ring-2 transition-transform"
                          [style.background]="c"
                          [class]="uColor() === c ? 'ring-slate-900 scale-110' : 'ring-transparent'"
                          [attr.aria-label]="'Color ' + c"
                          (click)="uColor.set(c)"></button>
                }
              </div>
            </div>
          }
        </div>

        <button type="button" class="btn-secundario btn-sm" (click)="generarClave()">
          Generar contraseña segura
        </button>

        @if (errorUsuario()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorUsuario() }}
          </p>
        }

        <p class="rounded-lg bg-slate-50 ring-1 ring-slate-200 px-3 py-2.5 text-xs text-slate-600">
          Anote la contraseña antes de guardar: no se puede volver a consultar, solo
          restablecer. Pídale a la persona que la cambie en su primer ingreso desde
          <strong>Contraseña</strong>, en el menú lateral.
        </p>
      </div>

      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgUsuario.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="!usuarioValido() || guardando()"
                (click)="guardarUsuario()">
          {{ guardando() ? 'Creando…' : 'Crear usuario' }}
        </button>
      </div>
    </app-dialogo>

    <!-- ============ Restablecer contraseña ============ -->
    <app-dialogo [(abierto)]="dlgClave" titulo="Restablecer contraseña"
                 [subtitulo]="usuarioClave()?.nombre_completo ?? ''">
      <div class="space-y-4">
        <p class="text-sm text-slate-600">
          La contraseña anterior deja de servir de inmediato. Entréguesela a la persona por
          un medio seguro y pídale que la cambie al entrar.
        </p>
        <div>
          <label class="etiqueta" for="rc-1">Nueva contraseña</label>
          <div class="flex gap-2">
            <input id="rc-1" class="campo" [type]="verClave() ? 'text' : 'password'"
                   autocomplete="new-password"
                   [value]="rcClave()" (input)="rcClave.set($any($event.target).value)">
            <button type="button" class="btn-secundario btn-sm shrink-0"
                    (click)="verClave.set(!verClave())">{{ verClave() ? 'Ocultar' : 'Ver' }}</button>
          </div>
          <p class="ayuda">Mínimo 10 caracteres.</p>
        </div>
        <button type="button" class="btn-secundario btn-sm" (click)="rcClave.set(claveAleatoria())">
          Generar contraseña segura
        </button>
        @if (errorClave()) {
          <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
            {{ errorClave() }}
          </p>
        }
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgClave.set(false)">Cancelar</button>
        <button type="button" class="btn-primario"
                [disabled]="rcClave().length < 10 || guardando()" (click)="guardarClave()">
          {{ guardando() ? 'Guardando…' : 'Restablecer' }}
        </button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgTratamiento" [titulo]="tratEdit()['id'] ? 'Editar tratamiento' : 'Nuevo tratamiento'">
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="etiqueta" for="t-cod">Código</label>
          <input id="t-cod" class="campo font-mono uppercase" maxlength="8"
                 [value]="tratEdit()['codigo'] ?? ''"
                 (input)="setTrat('codigo', $any($event.target).value.toUpperCase())">
        </div>
        <div>
          <label class="etiqueta" for="t-nom">Nombre</label>
          <input id="t-nom" class="campo" [value]="tratEdit()['nombre'] ?? ''"
                 (input)="setTrat('nombre', $any($event.target).value)">
        </div>
        <div class="sm:col-span-2">
          <label class="etiqueta" for="t-desc">Descripción</label>
          <input id="t-desc" class="campo" [value]="tratEdit()['descripcion'] ?? ''"
                 (input)="setTrat('descripcion', $any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="t-dur">Duración (min)</label>
          <input id="t-dur" class="campo" type="number" min="5" max="480"
                 [value]="tratEdit()['duracion_min'] ?? 30"
                 (input)="setTrat('duracion_min', +$any($event.target).value)">
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                 [checked]="tratEdit()['requiere_nota'] === true"
                 (change)="setTrat('requiere_nota', $any($event.target).checked)">
          Exige nota clínica
        </label>
        <label class="sm:col-span-2 flex items-center gap-2 text-sm">
          <input type="checkbox" class="rounded border-slate-300 text-marca-600"
                 [checked]="tratEdit()['activo'] !== false"
                 (change)="setTrat('activo', $any($event.target).checked)">
          Activo
        </label>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgTratamiento.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="guardando()"
                (click)="guardarTratamiento()">Guardar</button>
      </div>
    </app-dialogo>

    <app-dialogo [(abierto)]="dlgHorario" titulo="Agregar horario">
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="etiqueta" for="h-dia">Día</label>
          <select id="h-dia" class="campo" [value]="hDia()" (change)="hDia.set(+$any($event.target).value)">
            @for (d of dias; track $index) { <option [value]="$index">{{ d }}</option> }
          </select>
        </div>
        <div>
          <label class="etiqueta" for="h-fis">Fisioterapeuta</label>
          <select id="h-fis" class="campo" [value]="hFisio()" (change)="hFisio.set($any($event.target).value)">
            <option value="">Toda la clínica</option>
            @for (f of fisios(); track f.id) { <option [value]="f.id">{{ f.nombre_completo }}</option> }
          </select>
        </div>
        <div>
          <label class="etiqueta" for="h-ini">Desde</label>
          <input id="h-ini" class="campo" type="time" [value]="hInicio()"
                 (input)="hInicio.set($any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="h-fin">Hasta</label>
          <input id="h-fin" class="campo" type="time" [value]="hFin()"
                 (input)="hFin.set($any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="h-cup">Cupos simultáneos</label>
          <input id="h-cup" class="campo" type="number" min="1" max="20"
                 [value]="hCupos()" (input)="hCupos.set(+$any($event.target).value)">
        </div>
      </div>
      <div acciones class="flex justify-end gap-2">
        <button type="button" class="btn-secundario" (click)="dlgHorario.set(false)">Cancelar</button>
        <button type="button" class="btn-primario" [disabled]="guardando()"
                (click)="guardarHorario()">Agregar</button>
      </div>
    </app-dialogo>
  `,
})
export class Administracion {
  private readonly pacientes = inject(PacientesService);
  private readonly catalogos = inject(CatalogosService);
  private readonly sb = inject(SupabaseService);
  private readonly avisos = inject(AvisosService);
  readonly auth = inject(AuthService);

  readonly secciones: Array<{ id: Seccion; etiqueta: string }> = [
    { id: 'duplicados', etiqueta: 'Duplicados' },
    { id: 'usuarios', etiqueta: 'Personal' },
    { id: 'tratamientos', etiqueta: 'Tratamientos' },
    { id: 'horarios', etiqueta: 'Horarios' },
    { id: 'auditoria', etiqueta: 'Auditoría' },
    { id: 'ajustes', etiqueta: 'Ajustes' },
  ];
  readonly roles: RolUsuario[] = ['superadmin', 'admin', 'recepcion', 'fisioterapeuta'];
  readonly dias = DIAS;

  readonly ajustes = [
    { clave: 'nombre_clinica', etiqueta: 'Nombre de la clínica', tipo: 'text', ayuda: 'Aparece en el sitio público y en los mensajes.' },
    { clave: 'url_publica', etiqueta: 'URL pública', tipo: 'text', ayuda: 'Base de los enlaces que se envían al paciente.' },
    { clave: 'telefono_clinica', etiqueta: 'Teléfono', tipo: 'text', ayuda: '' },
    { clave: 'whatsapp_clinica', etiqueta: 'WhatsApp', tipo: 'text', ayuda: '' },
    { clave: 'direccion_clinica', etiqueta: 'Dirección', tipo: 'text', ayuda: '' },
    { clave: 'duracion_cita_min', etiqueta: 'Duración por cita (minutos)', tipo: 'number', ayuda: 'Se usa para generar los horarios disponibles.' },
    { clave: 'dias_anticipacion_max', etiqueta: 'Días de anticipación máxima', tipo: 'number', ayuda: 'Cuánto hacia adelante puede pedir cita un paciente.' },
    { clave: 'horas_anticipacion_min', etiqueta: 'Horas de anticipación mínima', tipo: 'number', ayuda: 'Evita solicitudes para dentro de un rato.' },
  ];

  readonly seccion = signal<Seccion>('duplicados');
  readonly cargando = signal(true);
  readonly guardando = signal(false);

  readonly duplicados = signal<Duplicado[]>([]);
  readonly personal = signal<Perfil[]>([]);
  /** Quien atiende, sin importar el rol: el superadministrador también pasa consulta. */
  readonly fisios = computed(() => this.personal().filter((p) => p.atiende && p.activo));
  readonly tratamientos = signal<Tratamiento[]>([]);
  readonly horarios = signal<any[]>([]);
  readonly auditoria = signal<RegistroAuditoria[]>([]);
  readonly config = signal<Record<string, unknown>>({});
  readonly filtroAccion = signal('');

  readonly conservar = signal<Record<string, string | undefined>>({});
  readonly motivos = signal<Record<string, string | undefined>>({});

  // --- Alta de usuarios ---------------------------------------------------
  readonly colores = ['#0d9488', '#7c3aed', '#db2777', '#ea580c', '#2563eb', '#65a30d'];
  readonly dlgUsuario = signal(false);
  readonly verClave = signal(false);
  readonly errorUsuario = signal('');
  readonly uNombre = signal('');
  readonly uEmail = signal('');
  readonly uClave = signal('');
  readonly uClave2 = signal('');
  readonly uRol = signal<RolUsuario>('recepcion');
  readonly uTelefono = signal('');
  readonly uColegiado = signal('');
  readonly uEspecialidad = signal('');
  readonly uColor = signal('#0d9488');
  readonly uAtiende = signal(false);

  readonly dlgClave = signal(false);
  readonly usuarioClave = signal<Perfil | null>(null);
  readonly rcClave = signal('');
  readonly errorClave = signal('');

  readonly dlgTratamiento = signal(false);
  readonly tratEdit = signal<Record<string, unknown>>({});
  readonly dlgHorario = signal(false);
  readonly hDia = signal(1);
  readonly hFisio = signal('');
  readonly hInicio = signal('08:00');
  readonly hFin = signal('12:00');
  readonly hCupos = signal(1);

  readonly fecha = fechaCorta;
  readonly fechaYHora = fechaHora;
  readonly dinero = moneda;

  dia(n: number): string { return DIAS[n] ?? '—'; }
  etiquetaRol(r: RolUsuario): string { return ETIQUETAS_ROL[r] ?? r; }

  motivoTexto(m: string): string {
    return {
      nombre_similar: 'Nombres muy parecidos',
      telefono_igual: 'Mismo teléfono',
      email_igual: 'Mismo correo',
    }[m] ?? m;
  }

  ladoA(d: Duplicado) {
    return { id: d.a_id, nombre: d.a_nombre, dpi: d.a_dpi, telefono: d.a_telefono, email: d.a_email, citas: d.a_citas, creado: d.a_creado };
  }
  ladoB(d: Duplicado) {
    return { id: d.b_id, nombre: d.b_nombre, dpi: d.b_dpi, telefono: d.b_telefono, email: d.b_email, citas: d.b_citas, creado: d.b_creado };
  }

  constructor() { void this.cargar(); }

  cambiar(s: Seccion) { this.seccion.set(s); void this.cargar(); }

  private async cargar() {
    this.cargando.set(true);
    try {
      switch (this.seccion()) {
        case 'duplicados':
          this.duplicados.set(await this.pacientes.duplicados());
          break;
        case 'usuarios':
          this.personal.set(await this.catalogos.personal());
          break;
        case 'tratamientos':
          this.tratamientos.set(await this.catalogos.tratamientos(false));
          break;
        case 'horarios':
          this.horarios.set(await this.catalogos.horarios());
          if (!this.personal().length) this.personal.set(await this.catalogos.personal());
          break;
        case 'auditoria':
          await this.cargarAuditoria();
          break;
        case 'ajustes':
          this.config.set(await this.catalogos.configuracion());
          break;
      }
    } catch (e) {
      this.avisos.error('No se pudo cargar la sección.');
      console.error(e);
    } finally {
      this.cargando.set(false);
    }
  }

  private async cargarAuditoria() {
    let q = this.sb.desde('auditoria').select('*');
    if (this.filtroAccion()) q = q.eq('accion', this.filtroAccion());
    const { data } = await q.order('ocurrido_en', { ascending: false }).limit(200);
    this.auditoria.set((data ?? []) as RegistroAuditoria[]);
  }

  filtrarAuditoria(e: Event) {
    this.filtroAccion.set((e.target as HTMLSelectElement).value);
    void this.cargarAuditoria();
  }

  // --- Duplicados ---------------------------------------------------------

  elegirConservar(dupId: string, pacienteId: string) {
    this.conservar.update((c) => ({ ...c, [dupId]: pacienteId }));
  }

  setMotivo(dupId: string, texto: string) {
    this.motivos.update((m) => ({ ...m, [dupId]: texto }));
  }

  async fusionar(d: Duplicado) {
    const destino = this.conservar()[d.id];
    const origen = destino === d.a_id ? d.b_id : d.a_id;
    const motivo = (this.motivos()[d.id] ?? '').trim();
    if (!destino || motivo.length < 5) return;

    this.guardando.set(true);
    try {
      const r = await this.pacientes.fusionar(origen, destino, motivo);
      if (!r.ok) {
        this.avisos.error('No se pudo fusionar: ' + (r.error ?? 'error desconocido'));
        return;
      }
      this.avisos.exito('Fichas fusionadas. Todo el historial quedó en la ficha conservada.');
      await this.cargar();
    } catch (e) {
      this.avisos.error('No se pudo fusionar.');
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  async descartar(d: Duplicado) {
    try {
      await this.pacientes.descartarDuplicado(d.id, 'Revisado: son personas distintas');
      this.avisos.info('Marcado como no duplicado.');
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo descartar.');
    }
  }

  // --- Usuarios -----------------------------------------------------------

  readonly uEmailOk = computed(() => /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(this.uEmail().trim()));

  readonly usuarioValido = computed(() =>
    this.uEmailOk()
    && this.uNombre().trim().split(/\s+/).length >= 2
    && this.uNombre().trim().length >= 5
    && this.uClave().length >= 10
    && this.uClave() === this.uClave2(),
  );

  readonly descripcionRol = computed(() => ({
    superadmin: 'Control total, incluye gestión de usuarios y configuración.',
    admin: 'Todo salvo crear usuarios y cambiar roles.',
    recepcion: 'Coordina citas y pagos. No ve notas clínicas ni antecedentes.',
    fisioterapeuta: 'Ve el expediente clínico solo de los pacientes que atiende.',
  } as Record<RolUsuario, string>)[this.uRol()]);

  /** Contraseña legible pero fuerte, sin caracteres que se confundan al dictar. */
  claveAleatoria(): string {
    const abc = 'abcdefghijkmnopqrstuvwxyz';
    const ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const num = '23456789';
    const sig = '!@#$%&*';
    const todo = abc + ABC + num + sig;
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    // Se garantiza al menos uno de cada tipo.
    const base = [
      ABC[bytes[0] % ABC.length],
      abc[bytes[1] % abc.length],
      num[bytes[2] % num.length],
      sig[bytes[3] % sig.length],
    ];
    for (let i = 4; i < 14; i++) base.push(todo[bytes[i] % todo.length]);
    return base.join('');
  }

  generarClave() {
    const c = this.claveAleatoria();
    this.uClave.set(c);
    this.uClave2.set(c);
    this.verClave.set(true);
  }

  abrirNuevoUsuario() {
    this.uNombre.set(''); this.uEmail.set(''); this.uClave.set(''); this.uClave2.set('');
    this.uRol.set('recepcion'); this.uTelefono.set(''); this.uColegiado.set('');
    this.uEspecialidad.set(''); this.uColor.set('#0d9488'); this.uAtiende.set(false);
    this.verClave.set(false); this.errorUsuario.set('');
    this.dlgUsuario.set(true);
  }

  /** El rol arrastra la marca de atender en los dos extremos: fisio sí, recepción no. */
  cambiarRolNuevo(rol: RolUsuario) {
    this.uRol.set(rol);
    if (rol === 'fisioterapeuta') this.uAtiende.set(true);
    else if (rol === 'recepcion') this.uAtiende.set(false);
  }

  async guardarUsuario() {
    if (!this.usuarioValido()) return;
    this.guardando.set(true);
    this.errorUsuario.set('');
    try {
      const r = await this.catalogos.crearUsuario({
        email: this.uEmail().trim(),
        clave: this.uClave(),
        nombre: this.uNombre().trim(),
        rol: this.uRol(),
        telefono: this.uTelefono().trim() || null,
        colegiado: this.uColegiado().trim() || null,
        especialidad: this.uEspecialidad().trim() || null,
        color: this.uAtiende() ? this.uColor() : null,
        atiende: this.uAtiende(),
      });

      if (!r.ok) {
        this.errorUsuario.set(r.mensaje ?? 'No se pudo crear el usuario.');
        return;
      }
      this.avisos.exito(`Usuario ${this.uEmail().trim()} creado. Ya puede iniciar sesión.`);
      this.dlgUsuario.set(false);
      await this.cargar();
    } catch (e) {
      this.errorUsuario.set(
        e instanceof Error && /insufficient|permission/i.test(e.message)
          ? 'Solo un superadministrador puede crear usuarios.'
          : 'No se pudo crear el usuario.',
      );
      console.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  abrirClave(p: Perfil) {
    this.usuarioClave.set(p);
    this.rcClave.set('');
    this.errorClave.set('');
    this.verClave.set(false);
    this.dlgClave.set(true);
  }

  async guardarClave() {
    const p = this.usuarioClave();
    if (!p || this.rcClave().length < 10) return;
    this.guardando.set(true);
    this.errorClave.set('');
    try {
      const r = await this.catalogos.restablecerContrasena(p.id, this.rcClave());
      if (!r.ok) {
        this.errorClave.set(r.mensaje ?? 'No se pudo restablecer la contraseña.');
        return;
      }
      this.avisos.exito(`Contraseña de ${p.nombre_completo} restablecida.`);
      this.dlgClave.set(false);
    } catch {
      this.errorClave.set('Solo un superadministrador puede restablecer contraseñas.');
    } finally {
      this.guardando.set(false);
    }
  }

  async cambiarRol(p: Perfil, rol: RolUsuario) {
    try {
      const { error } = await this.sb.desde('perfiles').update({ rol }).eq('id', p.id);
      if (error) throw error;
      this.avisos.exito(`Rol de ${p.nombre_completo} actualizado.`);
      await this.cargar();
    } catch {
      this.avisos.error('Solo un superadministrador puede cambiar roles.');
      await this.cargar();
    }
  }

  async alternarActivo(p: Perfil) {
    try {
      const { error } = await this.sb.desde('perfiles').update({ activo: !p.activo }).eq('id', p.id);
      if (error) throw error;
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo cambiar el estado del usuario.');
    }
  }

  /**
   * Marca o desmarca que esa persona pasa consulta. Al desmarcarla deja de
   * aparecer en la agenda, pero las citas y notas que ya firmó no se tocan.
   */
  async alternarAtiende(p: Perfil, atiende: boolean) {
    try {
      await this.catalogos.marcarAtiende(p.id, atiende);
      this.avisos.exito(atiende
        ? `${p.nombre_completo} ya puede atender pacientes.`
        : `${p.nombre_completo} deja de aparecer en la agenda.`);
      await this.cargar();
    } catch {
      this.avisos.error('Solo un superadministrador define quién atiende pacientes.');
      await this.cargar();
    }
  }

  // --- Tratamientos -------------------------------------------------------

  abrirTratamiento(t: Tratamiento | null) {
    this.tratEdit.set(t ? { ...t } : { duracion_min: 30, activo: true, requiere_nota: false });
    this.dlgTratamiento.set(true);
  }

  setTrat(campo: string, valor: unknown) {
    this.tratEdit.update((t) => ({ ...t, [campo]: valor }));
  }

  async guardarTratamiento() {
    this.guardando.set(true);
    try {
      await this.catalogos.guardarTratamiento(this.tratEdit() as Partial<Tratamiento>);
      this.avisos.exito('Tratamiento guardado.');
      this.dlgTratamiento.set(false);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo guardar el tratamiento.');
    } finally {
      this.guardando.set(false);
    }
  }

  // --- Horarios -----------------------------------------------------------

  async guardarHorario() {
    this.guardando.set(true);
    try {
      await this.catalogos.guardarHorario({
        dia_semana: this.hDia(),
        fisioterapeuta_id: this.hFisio() || null,
        hora_inicio: this.hInicio(),
        hora_fin: this.hFin(),
        cupos: this.hCupos(),
      });
      this.avisos.exito('Horario agregado.');
      this.dlgHorario.set(false);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo agregar el horario. Revise que la hora final sea mayor.');
    } finally {
      this.guardando.set(false);
    }
  }

  async borrarHorario(id: string) {
    try {
      await this.catalogos.eliminarHorario(id);
      await this.cargar();
    } catch {
      this.avisos.error('No se pudo eliminar el horario.');
    }
  }

  // --- Ajustes ------------------------------------------------------------

  valorConfig(clave: string): string {
    const v = this.config()[clave];
    return v === null || v === undefined ? '' : String(v);
  }

  setConfig(clave: string, valor: string, tipo: string) {
    this.config.update((c) => ({ ...c, [clave]: tipo === 'number' ? Number(valor) : valor }));
  }

  async guardarAjustes() {
    this.guardando.set(true);
    try {
      const c = this.config();
      for (const a of this.ajustes) {
        await this.catalogos.guardarConfiguracion(a.clave, c[a.clave]);
      }
      this.avisos.exito('Configuración guardada.');
    } catch {
      this.avisos.error('No se pudo guardar la configuración.');
    } finally {
      this.guardando.set(false);
    }
  }
}
