import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { environment } from '../../environments/environment';

@Component({
  selector: 'app-publico-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="min-h-dvh flex flex-col">
      <header class="sticky top-0 z-30 bg-white/90 backdrop-blur border-b border-slate-200">
        <div class="mx-auto max-w-5xl px-4 h-16 flex items-center justify-between gap-4">
          <a routerLink="/" class="flex items-center gap-2.5 group">
            <span class="w-9 h-9 rounded-xl bg-marca-600 grid place-items-center text-white shrink-0">
              <svg viewBox="0 0 24 24" class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round"
                      d="M3 12h3l2.5-6 3.5 12 3-9 2 3h4"/>
              </svg>
            </span>
            <span class="font-semibold text-slate-900 text-lg tracking-tight">{{ clinica.nombre }}</span>
          </a>

          <nav class="flex items-center gap-1 sm:gap-2">
            <a routerLink="/" routerLinkActive="text-marca-700 bg-marca-50"
               [routerLinkActiveOptions]="{ exact: true }"
               class="hidden sm:inline-flex btn-fantasma btn-sm">Inicio</a>
            <a routerLink="/solicitar" class="btn-primario btn-sm sm:text-sm sm:px-4 sm:py-2">
              Solicitar cita
            </a>
          </nav>
        </div>
      </header>

      <main class="flex-1"><router-outlet /></main>

      <footer class="border-t border-slate-200 bg-white">
        <div class="mx-auto max-w-5xl px-4 py-8 text-sm text-slate-500
                    flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
          <div>
            <p class="font-medium text-slate-700">{{ clinica.nombre }}</p>
            @if (clinica.direccion) { <p>{{ clinica.direccion }}</p> }
            @if (clinica.telefono) { <p>Tel. {{ clinica.telefono }}</p> }
          </div>
          <div class="flex flex-col sm:items-end gap-1">
            <a routerLink="/politica-de-datos" class="hover:text-marca-700">Política de tratamiento de datos</a>
            <a routerLink="/acceso" class="text-slate-400 hover:text-slate-600 text-xs">Acceso del personal</a>
            <p class="text-xs text-slate-400 mt-1">
              Desarrollado por
              <a href="https://www.techsolutionsgt.dev/" target="_blank" rel="noopener"
                 class="font-medium text-slate-500 hover:text-marca-700">TechSolutions GT</a>
            </p>
          </div>
        </div>
      </footer>
    </div>
  `,
})
export class PublicoLayout {
  readonly clinica = environment.clinica;
}
