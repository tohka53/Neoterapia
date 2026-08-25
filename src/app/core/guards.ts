import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';
import { RolUsuario } from './modelos';

/** Espera a que termine de restaurarse la sesión antes de decidir. */
async function esperarSesion(auth: AuthService): Promise<void> {
  let intentos = 0;
  while (auth.cargando() && intentos < 100) {
    await new Promise((r) => setTimeout(r, 40));
    intentos++;
  }
}

export const guardPersonal: CanActivateFn = async (_ruta, estado) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await esperarSesion(auth);
  if (auth.autenticado()) return true;
  return router.createUrlTree(['/acceso'], { queryParams: { destino: estado.url } });
};

/** Restringe una ruta a ciertos roles. */
export function guardRol(...roles: RolUsuario[]): CanActivateFn {
  return async () => {
    const auth = inject(AuthService);
    const router = inject(Router);
    await esperarSesion(auth);
    if (!auth.autenticado()) return router.createUrlTree(['/acceso']);
    const rol = auth.rol();
    if (rol && roles.includes(rol)) return true;
    return router.createUrlTree(['/panel/sin-permiso']);
  };
}

/** Si ya hay sesión, no tiene sentido volver a la pantalla de acceso. */
export const guardInvitado: CanActivateFn = async () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await esperarSesion(auth);
  return auth.autenticado() ? router.createUrlTree(['/panel']) : true;
};
