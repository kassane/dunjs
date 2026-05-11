function factorial(n) {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
}

function fibonacci(n) {
  if (n <= 1) return n;
  let a = 0, b = 1;
  for (let i = 2; i <= n; i++) { let t = b; b = a + b; a = t; }
  return b;
}

module.exports = { factorial, fibonacci };
