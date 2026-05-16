// Type error: accessing a property that doesn't exist on the type.
interface User { name: string; age: number; }
const u: User = { name: "a", age: 5 };
console.log(u.emaillll);  // typo, no such field
