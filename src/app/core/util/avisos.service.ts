import { Injectable, signal } from '@angular/core';

export interface Aviso {
  id: number;
  tipo: 'exito' | 'error' | 'info';
  texto: string;
}

@Injectable({ providedIn: 'root' })
export class AvisosService {
  private siguiente = 1;
  readonly lista = signal<Aviso[]>([]);

  exito(texto: string) { this.mostrar('exito', texto); }
  error(texto: string) { this.mostrar('error', texto, 7000); }
  info(texto: string)  { this.mostrar('info', texto); }

  private mostrar(tipo: Aviso['tipo'], texto: string, ms = 4200) {
    const id = this.siguiente++;
    this.lista.update((l) => [...l, { id, tipo, texto }]);
    setTimeout(() => this.cerrar(id), ms);
  }

  cerrar(id: number) {
    this.lista.update((l) => l.filter((a) => a.id !== id));
  }
}
