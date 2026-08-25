import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { AvisosService } from '../core/util/avisos.service';

@Component({
  selector: 'app-cambiar-clave',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="p-4 sm:p-6 lg:p-8 max-w-md mx-auto">
      <h1 class="text-2xl font-bold tracking-tight mb-1">Cambiar contraseña</h1>
      <p class="text-sm text-slate-500 mb-6">Mínimo 10 caracteres.</p>

      <div class="tarjeta tarjeta-cuerpo space-y-4">
        <div>
          <label class="etiqueta" for="n1">Nueva contraseña</label>
          <input id="n1" class="campo" type="password" autocomplete="new-password"
                 [value]="clave()" (input)="clave.set($any($event.target).value)">
        </div>
        <div>
          <label class="etiqueta" for="n2">Repita la contraseña</label>
          <input id="n2" class="campo" type="password" autocomplete="new-password"
                 [class.campo-error]="repetir() !== '' && !coinciden()"
                 [value]="repetir()" (input)="repetir.set($any($event.target).value)">
          @if (repetir() !== '' && !coinciden()) {
            <p class="error-texto">Las contraseñas no coinciden.</p>
          }
        </div>
        <button type="button" class="btn-primario w-full" [disabled]="!valida() || ocupado()"
                (click)="guardar()">
          {{ ocupado() ? 'Guardando…' : 'Actualizar contraseña' }}
        </button>
      </div>
    </div>
  `,
})
export class CambiarClave {
  private readonly auth = inject(AuthService);
  private readonly avisos = inject(AvisosService);
  private readonly router = inject(Router);

  readonly clave = signal('');
  readonly repetir = signal('');
  readonly ocupado = signal(false);

  readonly coinciden = computed(() => this.clave() === this.repetir());
  readonly valida = computed(() => this.clave().length >= 10 && this.coinciden());

  async guardar() {
    if (!this.valida()) return;
    this.ocupado.set(true);
    try {
      await this.auth.cambiarContrasena(this.clave());
      this.avisos.exito('Contraseña actualizada.');
      await this.router.navigate(['/panel']);
    } catch (e) {
      this.avisos.error(e instanceof Error ? e.message : 'No se pudo actualizar.');
    } finally {
      this.ocupado.set(false);
    }
  }
}
