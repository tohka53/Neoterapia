import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-inicio',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <section class="mx-auto max-w-5xl px-4 pt-14 pb-10 sm:pt-20">
      <div class="grid gap-10 lg:grid-cols-2 lg:items-center">
        <div>
          <p class="inline-flex items-center gap-2 rounded-full bg-marca-50 text-marca-800
                    px-3 py-1 text-xs font-medium ring-1 ring-marca-200">
            Sin registro · sin contraseñas
          </p>
          <h1 class="mt-4 text-4xl sm:text-5xl font-bold tracking-tight text-slate-900 leading-[1.1]">
            Su cita de fisioterapia,<br class="hidden sm:block"> en un solo formulario
          </h1>
          <p class="mt-5 text-lg text-slate-600 max-w-prose">
            No necesita crear una cuenta ni recordar una contraseña. Llene el formulario,
            reciba su código de referencia y nosotros le confirmamos por WhatsApp o correo.
          </p>
          <div class="mt-8 flex flex-wrap gap-3">
            <a routerLink="/solicitar" class="btn-primario px-6 py-3 text-base">Solicitar mi cita</a>
            <a href="#como-funciona" class="btn-secundario px-6 py-3 text-base">Cómo funciona</a>
          </div>
        </div>

        <div class="relative">
          <div class="tarjeta tarjeta-cuerpo max-w-sm mx-auto">
            <p class="text-xs uppercase tracking-wide text-slate-400 font-semibold">Lo que necesitamos</p>
            <ul class="mt-4 space-y-3 text-sm">
              @for (d of datos; track d) {
                <li class="flex items-start gap-3">
                  <span class="mt-0.5 w-5 h-5 rounded-full bg-marca-100 text-marca-700 grid place-items-center shrink-0">
                    <svg viewBox="0 0 24 24" class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="3">
                      <path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7"/>
                    </svg>
                  </span>
                  <span class="text-slate-700">{{ d }}</span>
                </li>
              }
            </ul>
            <p class="mt-5 pt-4 border-t border-slate-100 text-xs text-slate-500 leading-relaxed">
              Su DPI se usa únicamente para vincular sus visitas a un mismo expediente
              interno. Nunca se muestra completo en pantalla.
            </p>
          </div>
        </div>
      </div>
    </section>

    <section id="como-funciona" class="bg-white border-y border-slate-200">
      <div class="mx-auto max-w-5xl px-4 py-14">
        <h2 class="text-2xl font-semibold">Cómo funciona</h2>
        <ol class="mt-8 grid gap-6 sm:grid-cols-3">
          @for (p of pasos; track p.n) {
            <li class="relative">
              <span class="text-marca-600 font-bold text-sm">Paso {{ p.n }}</span>
              <h3 class="mt-1 text-base font-semibold">{{ p.titulo }}</h3>
              <p class="mt-1.5 text-sm text-slate-600 leading-relaxed">{{ p.texto }}</p>
            </li>
          }
        </ol>
      </div>
    </section>

    <section class="mx-auto max-w-5xl px-4 py-14">
      <h2 class="text-2xl font-semibold">Preguntas frecuentes</h2>
      <div class="mt-6 divide-y divide-slate-200 border-y border-slate-200">
        @for (f of faq; track f.p) {
          <details class="group py-4">
            <summary class="flex items-center justify-between cursor-pointer list-none font-medium text-slate-800">
              {{ f.p }}
              <span class="text-slate-400 transition-transform group-open:rotate-45 text-xl leading-none">+</span>
            </summary>
            <p class="mt-2.5 text-sm text-slate-600 leading-relaxed max-w-prose">{{ f.r }}</p>
          </details>
        }
      </div>
    </section>
  `,
})
export class Inicio {
  readonly datos = [
    'Su DPI',
    'Su nombre completo',
    'Un teléfono o WhatsApp, o un correo electrónico',
    'La fecha y el horario que prefiere',
    'Las zonas del cuerpo donde tiene molestia',
  ];

  readonly pasos = [
    { n: 1, titulo: 'Llene el formulario', texto: 'Toma dos minutos. Marque en el mapa corporal dónde le duele y qué tan intenso es.' },
    { n: 2, titulo: 'Reciba su código', texto: 'Le damos un código de referencia como NT-ABC-1234. Con eso identificamos su cita si nos escribe.' },
    { n: 3, titulo: 'Le confirmamos', texto: 'La clínica revisa la disponibilidad y le responde por su canal preferido con la hora final.' },
  ];

  readonly faq = [
    {
      p: '¿Tengo que crear una cuenta?',
      r: 'No. NeoTerapia no maneja cuentas de pacientes. Todo el seguimiento se hace por correo o WhatsApp usando su código de referencia.',
    },
    {
      p: '¿Para qué piden mi DPI?',
      r: 'Es la única forma confiable de saber que usted es la misma persona que vino antes, y así conservar su historial en un solo expediente. Nunca se muestra completo en los listados y su acceso queda registrado.',
    },
    {
      p: '¿Puedo cancelar o reprogramar?',
      r: 'Sí. En el mensaje de confirmación le enviamos enlaces directos para confirmar asistencia o cancelar. También puede escribirnos citando su código.',
    },
    {
      p: '¿Puedo ver mi historial clínico en la web?',
      r: 'No. El expediente clínico es de uso interno de la clínica. Si necesita una copia o una constancia, solicítela directamente en recepción.',
    },
    {
      p: '¿Qué pasa si me equivoqué al escribir mi DPI?',
      r: 'Escríbanos con su código de referencia. El personal puede corregirlo y unir sus expedientes sin que usted pierda su historial.',
    },
  ];
}
