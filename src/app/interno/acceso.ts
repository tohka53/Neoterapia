import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { AvisosService } from '../core/util/avisos.service';

@Component({
  selector: 'app-acceso',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <div class="min-h-dvh grid lg:grid-cols-2">
      <div class="flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-sm">
          <a routerLink="/" class="inline-flex items-center gap-2.5 mb-8">
            <span class="w-9 h-9 rounded-xl bg-marca-600 grid place-items-center text-white">
              <svg viewBox="0 0 24 24" class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 12h3l2.5-6 3.5 12 3-9 2 3h4"/>
              </svg>
            </span>
            <span class="font-semibold text-lg tracking-tight">NeoTerapia</span>
          </a>

          <h1 class="text-2xl font-bold tracking-tight">Acceso del personal</h1>
          <p class="mt-1.5 text-sm text-slate-600">
            Esta pantalla es solo para el equipo de la clínica.
            Los pacientes no necesitan cuenta.
          </p>

          <form class="mt-8 space-y-4" (submit)="entrar($event)">
            <div>
              <label class="etiqueta" for="email">Correo</label>
              <input id="email" class="campo" type="email" autocomplete="username" required
                     [value]="email()" (input)="email.set($any($event.target).value)">
            </div>
            <div>
              <label class="etiqueta" for="clave">Contraseña</label>
              <input id="clave" class="campo" type="password" autocomplete="current-password" required
                     [value]="clave()" (input)="clave.set($any($event.target).value)">
            </div>

            @if (error()) {
              <p class="rounded-lg bg-rose-50 ring-1 ring-rose-200 px-3 py-2 text-sm text-rose-800">
                {{ error() }}
              </p>
            }

            <button type="submit" class="btn-primario w-full py-3" [disabled]="ocupado()">
              {{ ocupado() ? 'Entrando…' : 'Entrar' }}
            </button>
          </form>

          <button type="button" class="mt-4 text-sm text-slate-500 hover:text-marca-700"
                  (click)="recuperar()">¿Olvidó su contraseña?</button>

          <p class="mt-10 text-xs text-slate-400">
            <a routerLink="/" class="hover:text-slate-600">← Volver al sitio público</a>
          </p>
        </div>
      </div>

      <div class="hidden lg:flex items-center justify-center bg-marca-700 text-white p-12">
        <div class="max-w-md">
          <blockquote class="text-2xl font-medium leading-snug">
            «El expediente se arma solo. Usted solo confirma la cita.»
          </blockquote>
          <div class="mt-8 space-y-3 text-marca-100 text-sm">
            @for (p of puntos; track p) {
              <p class="flex gap-3">
                <span class="text-marca-300">—</span><span>{{ p }}</span>
              </p>
            }
          </div>
        </div>
      </div>
    </div>
  `,
})
export class Acceso {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly avisos = inject(AvisosService);

  readonly email = signal('');
  readonly clave = signal('');
  readonly ocupado = signal(false);
  readonly error = signal('');

  readonly puntos = [
    'Cada solicitud crea o reutiliza la ficha del paciente usando el DPI.',
    'Los DPI se muestran enmascarados y cada consulta completa queda auditada.',
    'Recepción coordina; el fisioterapeuta ve la clínica de sus pacientes.',
  ];

  async entrar(e: Event) {
    e.preventDefault();
    if (this.ocupado()) return;
    this.ocupado.set(true);
    this.error.set('');
    try {
      await this.auth.iniciarSesion(this.email(), this.clave());
      const destino = new URLSearchParams(location.search).get('destino');
      await this.router.navigateByUrl(destino ?? '/panel');
    } catch (err) {
      this.error.set(err instanceof Error ? err.message : 'No se pudo iniciar sesión.');
    } finally {
      this.ocupado.set(false);
    }
  }

  async recuperar() {
    if (!this.email().trim()) {
      this.avisos.info('Escriba su correo primero.');
      return;
    }
    try {
      await this.auth.enviarRecuperacion(this.email());
      this.avisos.exito('Si el correo existe, le llegará un enlace para restablecer la contraseña.');
    } catch {
      this.avisos.error('No se pudo enviar el correo de recuperación.');
    }
  }
}
