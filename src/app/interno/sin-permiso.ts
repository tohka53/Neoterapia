import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { ETIQUETAS_ROL } from '../core/modelos';

@Component({
  selector: 'app-sin-permiso',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <div class="p-8 max-w-lg mx-auto text-center">
      <div class="mx-auto w-12 h-12 rounded-full bg-slate-100 grid place-items-center mb-4">
        <span class="text-slate-400 text-xl">🔒</span>
      </div>
      <h1 class="text-xl font-semibold">Esta sección no está disponible para su rol</h1>
      <p class="mt-2 text-slate-600">
        Su usuario tiene el rol de <strong>{{ rol() }}</strong>. Si necesita acceso,
        solicítelo al administrador de la clínica.
      </p>
      <a routerLink="/panel/tablero" class="btn-primario mt-6">Volver al tablero</a>
    </div>
  `,
})
export class SinPermiso {
  private readonly auth = inject(AuthService);
  rol(): string {
    const r = this.auth.rol();
    return r ? ETIQUETAS_ROL[r] : 'sin rol';
  }
}
