import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { SupabaseService } from './supabase.service';
import { Perfil, RolUsuario } from './modelos';

/**
 * Sesión del PERSONAL de la clínica. El paciente nunca pasa por aquí.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly sb = inject(SupabaseService);
  private readonly router = inject(Router);

  readonly perfil = signal<Perfil | null>(null);
  readonly cargando = signal(true);

  readonly autenticado = computed(() => this.perfil() !== null);
  readonly rol = computed<RolUsuario | null>(() => this.perfil()?.rol ?? null);

  readonly esAdmin = computed(() => {
    const r = this.rol();
    return r === 'admin' || r === 'superadmin';
  });
  readonly esSuperadmin = computed(() => this.rol() === 'superadmin');
  readonly esRecepcion = computed(() => this.rol() === 'recepcion');
  readonly esFisio = computed(() => this.rol() === 'fisioterapeuta');
  /**
   * Pasa consulta. No es lo mismo que el rol: el superadministrador de una
   * clínica pequeña suele atender pacientes además de administrar.
   */
  readonly atiende = computed(() => this.perfil()?.atiende === true);
  /** Coordina agenda: recepción y administración. */
  readonly coordina = computed(() => this.esAdmin() || this.esRecepcion());
  /** Ve información clínica: fisioterapeutas y administración, nunca recepción. */
  readonly veClinico = computed(() => this.esAdmin() || this.esFisio());
  readonly veFinanzas = computed(() => this.esAdmin() || this.esRecepcion());

  constructor() {
    this.sb.cliente.auth.onAuthStateChange((evento) => {
      if (evento === 'SIGNED_OUT') {
        this.perfil.set(null);
      } else if (evento === 'SIGNED_IN' || evento === 'TOKEN_REFRESHED') {
        void this.cargarPerfil();
      }
    });
    void this.restaurar();
  }

  private async restaurar(): Promise<void> {
    this.cargando.set(true);
    const { data } = await this.sb.cliente.auth.getSession();
    if (data.session) await this.cargarPerfil();
    this.cargando.set(false);
  }

  private async cargarPerfil(): Promise<void> {
    const { data: usuario } = await this.sb.cliente.auth.getUser();
    if (!usuario.user) {
      this.perfil.set(null);
      return;
    }
    const { data, error } = await this.sb
      .desde('perfiles')
      .select('*')
      .eq('id', usuario.user.id)
      .maybeSingle();

    if (error || !data) {
      // Autenticó pero no tiene perfil: no es personal de la clínica.
      this.perfil.set(null);
      await this.sb.cliente.auth.signOut();
      return;
    }
    if (!(data as Perfil).activo) {
      this.perfil.set(null);
      await this.sb.cliente.auth.signOut();
      throw new Error('Su usuario está desactivado. Contacte al administrador.');
    }
    this.perfil.set(data as Perfil);
  }

  async iniciarSesion(email: string, contrasena: string): Promise<void> {
    const { error } = await this.sb.cliente.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password: contrasena,
    });
    if (error) {
      throw new Error(
        /invalid login/i.test(error.message)
          ? 'Correo o contraseña incorrectos.'
          : error.message,
      );
    }
    await this.cargarPerfil();
    if (!this.perfil()) {
      throw new Error('Este usuario no pertenece al personal de la clínica.');
    }
  }

  async cerrarSesion(): Promise<void> {
    await this.sb.cliente.auth.signOut();
    this.perfil.set(null);
    await this.router.navigate(['/acceso']);
  }

  async enviarRecuperacion(email: string): Promise<void> {
    const { error } = await this.sb.cliente.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      { redirectTo: `${location.origin}/panel/clave` },
    );
    if (error) throw new Error(error.message);
  }

  async cambiarContrasena(nueva: string): Promise<void> {
    const { error } = await this.sb.cliente.auth.updateUser({ password: nueva });
    if (error) throw new Error(error.message);
  }
}
