import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { environment } from '../../environments/environment';

@Component({
  selector: 'app-politica',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <article class="mx-auto max-w-2xl px-4 py-12 prose-slate">
      <h1 class="text-3xl font-bold tracking-tight">Política de tratamiento de datos</h1>
      <p class="mt-2 text-sm text-slate-500">Última actualización: {{ actualizado }}</p>

      @for (s of secciones; track s.titulo) {
        <section class="mt-8">
          <h2 class="text-lg font-semibold">{{ s.titulo }}</h2>
          @for (p of s.parrafos; track p) {
            <p class="mt-2.5 text-slate-700 leading-relaxed">{{ p }}</p>
          }
          @if (s.lista) {
            <ul class="mt-3 space-y-1.5 text-slate-700">
              @for (li of s.lista; track li) {
                <li class="flex gap-2.5"><span class="text-marca-600">•</span><span>{{ li }}</span></li>
              }
            </ul>
          }
        </section>
      }

      <p class="mt-10 pt-6 border-t border-slate-200 text-sm text-slate-500">
        ¿Dudas sobre sus datos? Escríbanos o pregunte en recepción.
        <a routerLink="/" class="text-marca-700 underline ml-1">Volver al inicio</a>
      </p>
    </article>
  `,
})
export class Politica {
  readonly clinica = environment.clinica.nombre;
  readonly actualizado = new Intl.DateTimeFormat('es-GT', {
    day: 'numeric', month: 'long', year: 'numeric',
  }).format(new Date());

  readonly secciones = [
    {
      titulo: 'Qué datos recolectamos',
      parrafos: ['Al solicitar una cita usted nos proporciona únicamente:'],
      lista: [
        'Número de DPI (o documento equivalente).',
        'Nombre completo.',
        'Teléfono, WhatsApp y/o correo electrónico.',
        'La fecha y el horario que prefiere.',
        'Las zonas del cuerpo donde siente molestia y su intensidad.',
        'Los comentarios que decida escribir.',
      ],
    },
    {
      titulo: 'Para qué los usamos',
      parrafos: [
        'Para agendar su cita, confirmarla, recordársela y brindarle la atención de fisioterapia solicitada.',
        'Su DPI cumple una función concreta: vincular todas sus visitas a un mismo expediente interno. Sin él, cada solicitud generaría un registro suelto y su historial se perdería.',
      ],
    },
    {
      titulo: 'Cómo los protegemos',
      parrafos: [
        'El DPI nunca se muestra completo en los listados del personal: aparece enmascarado. Solo la administración y el fisioterapeuta que le atiende pueden destaparlo, y cada consulta queda registrada en una bitácora que no puede modificarse ni borrarse.',
        'El personal de recepción ve únicamente lo necesario para coordinar su cita; no tiene acceso a notas clínicas ni antecedentes. Cada fisioterapeuta ve solamente la información de los pacientes que atiende.',
      ],
    },
    {
      titulo: 'Usted no tiene cuenta con nosotros',
      parrafos: [
        'No creamos usuarios de paciente, no le pedimos contraseña y no existe un portal donde consultar su expediente. Todo el seguimiento se hace por correo o WhatsApp.',
        'El código de referencia que le entregamos identifica su cita cuando se comunica con nosotros, pero no es una contraseña ni da acceso a información alguna. Los enlaces que le enviamos sirven para una sola acción (confirmar, cancelar o evaluar), vencen y no muestran su historial.',
      ],
    },
    {
      titulo: 'Con quién los compartimos',
      parrafos: [
        'Con nadie. Sus datos se usan exclusivamente dentro de la clínica para su atención, salvo requerimiento legal de autoridad competente.',
      ],
    },
    {
      titulo: 'Sus derechos',
      parrafos: [
        'Puede solicitar acceso a la información que tenemos sobre usted, pedir que corrijamos un dato equivocado (por ejemplo, un DPI mal digitado) o requerir una copia de su expediente. Diríjase a recepción con su documento de identificación.',
      ],
    },
  ];
}
