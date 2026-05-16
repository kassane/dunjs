// Type error: nullable / undefined access without check.
// Only catches under --strictNullChecks (default for `strict: true`).
function maybe(): string | null { return null; }
const s = maybe();
console.log(s.length);  // s could be null
