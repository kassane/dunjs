// `\p{Script=X}` / `\p{sc=X}` unicode property tests.
// Works natively on QuickJS / JSC; on V8 (no ICU) it goes through
// our unicode_props rewriter + runtime polyfill.

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

const tests = [
  ['Latin a', 'Latin', 'a', true],
  ['Latin 京', 'Latin', '京', false],
  ['Han 京', 'Han', '京', true],
  ['Han a', 'Han', 'a', false],
  ['Greek α', 'Greek', 'α', true],
  ['Cyrillic ж', 'Cyrillic', 'ж', true],
  ['Hiragana あ', 'Hiragana', 'あ', true],
  ['Katakana ア', 'Katakana', 'ア', true],
  ['Hebrew א', 'Hebrew', 'א', true],
  ['Arabic ع', 'Arabic', 'ع', true],
  ['Devanagari अ', 'Devanagari', 'अ', true],
  ['Thai ก', 'Thai', 'ก', true],
];

for (const [name, script, ch, expect] of tests) {
  const re = new RegExp('\\p{Script=' + script + '}', 'u');
  check(name, re.test(ch) === expect);
}

// Short-code form.
check('sc=Latn', new RegExp('\\p{sc=Latn}', 'u').test('a'));
check('sc=Hani', new RegExp('\\p{sc=Hani}', 'u').test('京'));

console.log('unicode_scripts:', passed + '/' + total, 'checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
