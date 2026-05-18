// Type-only inline modifiers + type alias chains.
// (Top-level type-only imports skipped for self-containment;
// stripper must erase `type` modifiers from re-exports / inline imports.)

// Inline `type` in destructure
import { join as _join } from "node:path";
type FsPath = string;

interface Renderable { render(): string }

// Type alias with embedded `;` inside generic
type Json = string | number | boolean | null | { [k: string]: Json } | Json[];

class Renderer<T extends Renderable> {
  constructor(private items: T[]) {}
  output(): string {
    return this.items.map(i => i.render()).join("|");
  }
}

class Card implements Renderable {
  constructor(private label: string) {}
  render(): string { return `[${this.label}]`; }
}

const r = new Renderer([new Card("A"), new Card("B"), new Card("C")]);
console.log(r.output());

const j: Json = { name: "X", values: [1, 2, null, { nested: true }] };
console.log((j as any).values[3].nested);
