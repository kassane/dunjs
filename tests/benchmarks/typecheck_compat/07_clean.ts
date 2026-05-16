// No type errors — should run normally.
interface User { name: string; }
function greet(u: User): string { return "hi " + u.name; }
const u: User = { name: "world" };
console.log(greet(u));
