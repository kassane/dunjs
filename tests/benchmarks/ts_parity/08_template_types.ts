// Template literal types (erased), template literals as expressions,
// tagged templates with mixed quotes.

type Route = `/${string}` | `/${string}/${string}`;
const r1: Route = "/users";
const r2: Route = "/users/42";

function sql(strings: TemplateStringsArray, ...values: unknown[]): {
  query: string;
  params: unknown[];
} {
  let q = "";
  for (let i = 0; i < strings.length; i++) {
    q += strings[i];
    if (i < values.length) q += "?";
  }
  return { query: q.trim().replace(/\s+/g, " "), params: values };
}

const limit = 10;
const role = "admin";
const result = sql`
  SELECT * FROM users
  WHERE role = ${role} AND age > 21
  LIMIT ${limit}
`;

console.log(r1, r2);
console.log(result.query);
console.log(JSON.stringify(result.params));

// Nested template + interpolation across types
type Greeting = `Hello, ${string}!`;
const g: Greeting = `Hello, ${'world'.toUpperCase()}!`;
console.log(g);
