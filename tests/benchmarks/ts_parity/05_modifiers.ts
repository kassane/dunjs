// Type-only modifiers in import, `satisfies`, `as const`,
// non-null assertion `!`, definite-assignment `!:`.

const palette = {
  red: [255, 0, 0],
  green: [0, 255, 0],
  blue: [0, 0, 255],
} as const satisfies Record<string, readonly [number, number, number]>;

class Service {
  endpoint!: string;
  init(): void { this.endpoint = "/api/v1"; }
}

const s = new Service();
s.init();
const ep = s.endpoint!;
console.log(ep);

// Type narrowing via assertion
function getNumber(x: number | null): number {
  return x! * 2;
}
console.log(getNumber(21));

// Iterate `as const` object — keys preserved
const keys = Object.keys(palette);
console.log(keys.sort().join(","));
console.log(palette.red.join("-"));
