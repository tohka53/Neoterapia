import { Routes } from '@angular/router';
import { guardInvitado, guardPersonal, guardRol } from './core/guards';

/**
 * Dos zonas, sin puntos de contacto:
 *
 *   /            → público. El paciente NO tiene cuenta, ni perfil, ni portal.
 *   /panel       → personal de la clínica, con sesión y rol.
 *
 * No existen rutas /registro, /mi-perfil ni /mis-citas: por diseño.
 */
export const routes: Routes = [
  {
    path: '',
    loadComponent: () => import('./publico/publico-layout').then((m) => m.PublicoLayout),
    children: [
      {
        path: '',
        loadComponent: () => import('./publico/inicio').then((m) => m.Inicio),
        title: 'NeoTerapia · Fisioterapia',
      },
      {
        path: 'solicitar',
        loadComponent: () => import('./publico/solicitar').then((m) => m.Solicitar),
        title: 'Solicitar cita · NeoTerapia',
      },
      {
        path: 'cita/:accion',
        loadComponent: () => import('./publico/accion-cita').then((m) => m.AccionCita),
        title: 'Su cita · NeoTerapia',
      },
      {
        path: 'politica-de-datos',
        loadComponent: () => import('./publico/politica').then((m) => m.Politica),
        title: 'Política de datos · NeoTerapia',
      },
    ],
  },

  {
    path: 'acceso',
    canActivate: [guardInvitado],
    loadComponent: () => import('./interno/acceso').then((m) => m.Acceso),
    title: 'Acceso del personal · NeoTerapia',
  },

  {
    path: 'panel',
    canActivate: [guardPersonal],
    loadComponent: () => import('./interno/panel-layout').then((m) => m.PanelLayout),
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'tablero' },
      {
        path: 'tablero',
        loadComponent: () => import('./interno/tablero').then((m) => m.Tablero),
        title: 'Tablero · NeoTerapia',
      },
      {
        path: 'solicitudes',
        loadComponent: () => import('./interno/solicitudes').then((m) => m.Solicitudes),
        title: 'Solicitudes · NeoTerapia',
      },
      {
        path: 'agenda',
        loadComponent: () => import('./interno/agenda').then((m) => m.Agenda),
        title: 'Agenda · NeoTerapia',
      },
      {
        path: 'pacientes',
        loadComponent: () => import('./interno/pacientes').then((m) => m.Pacientes),
        title: 'Pacientes · NeoTerapia',
      },
      {
        path: 'pacientes/:id',
        loadComponent: () => import('./interno/ficha-paciente').then((m) => m.FichaPaciente),
        title: 'Ficha del paciente · NeoTerapia',
      },
      {
        path: 'sesiones/:id',
        canActivate: [guardRol('superadmin', 'admin', 'fisioterapeuta')],
        loadComponent: () => import('./interno/sesion').then((m) => m.EditorSesion),
        title: 'Sesión clínica · NeoTerapia',
      },
      {
        path: 'pagos',
        canActivate: [guardRol('superadmin', 'admin', 'recepcion')],
        loadComponent: () => import('./interno/pagos').then((m) => m.Pagos),
        title: 'Pagos · NeoTerapia',
      },
      {
        path: 'alertas',
        canActivate: [guardRol('superadmin', 'admin', 'recepcion')],
        loadComponent: () => import('./interno/alertas').then((m) => m.Alertas),
        title: 'Alertas · NeoTerapia',
      },
      {
        path: 'administracion',
        canActivate: [guardRol('superadmin', 'admin')],
        loadComponent: () => import('./interno/administracion').then((m) => m.Administracion),
        title: 'Administración · NeoTerapia',
      },
      {
        path: 'clave',
        loadComponent: () => import('./interno/cambiar-clave').then((m) => m.CambiarClave),
        title: 'Cambiar contraseña · NeoTerapia',
      },
      {
        path: 'sin-permiso',
        loadComponent: () => import('./interno/sin-permiso').then((m) => m.SinPermiso),
        title: 'Sin permiso · NeoTerapia',
      },
    ],
  },

  { path: '**', redirectTo: '' },
];
