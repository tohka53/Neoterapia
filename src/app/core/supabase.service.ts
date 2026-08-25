import { Injectable } from '@angular/core';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';

/**
 * Cliente único de Supabase.
 *
 * Se configura sin persistencia de sesión para `anon`: el flujo público del
 * paciente no crea ninguna sesión, ni siquiera anónima. El almacenamiento local
 * solo se usa cuando inicia sesión personal de la clínica.
 */
@Injectable({ providedIn: 'root' })
export class SupabaseService {
  readonly cliente: SupabaseClient = createClient(
    environment.supabaseUrl,
    environment.supabaseKey,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        storageKey: 'neoterapia.sesion',
      },
      global: {
        headers: { 'x-cliente': 'neoterapia-web' },
      },
    },
  );

  /** Llama a una función de Postgres y lanza si falla. */
  async rpc<T>(nombre: string, parametros: Record<string, unknown> = {}): Promise<T> {
    const { data, error } = await this.cliente.rpc(nombre, parametros);
    if (error) throw new ErrorSupabase(error.message, error.code, nombre);
    return data as T;
  }

  /** Igual que `rpc`, pero devuelve `null` en vez de lanzar. Útil en listados. */
  async rpcSuave<T>(nombre: string, parametros: Record<string, unknown> = {}): Promise<T | null> {
    try {
      return await this.rpc<T>(nombre, parametros);
    } catch {
      return null;
    }
  }

  desde(tabla: string) {
    return this.cliente.from(tabla);
  }
}

export class ErrorSupabase extends Error {
  constructor(
    mensaje: string,
    readonly codigo?: string,
    readonly origen?: string,
  ) {
    super(mensaje);
    this.name = 'ErrorSupabase';
  }

  /** Traduce los errores más comunes a algo que un humano entienda. */
  get mensajeAmable(): string {
    if (this.codigo === '42501' || /permission denied|insufficient/i.test(this.message)) {
      return 'Su rol no tiene permiso para esta acción.';
    }
    if (this.codigo === '23505') return 'Ese registro ya existe.';
    if (this.codigo === '23514') return 'Los datos no cumplen una validación del sistema.';
    if (/JWT|not authenticated/i.test(this.message)) return 'Su sesión expiró. Vuelva a iniciar sesión.';
    return this.message;
  }
}
