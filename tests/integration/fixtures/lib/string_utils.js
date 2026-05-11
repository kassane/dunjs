// String utility library
function capitalize(s) {
  if (!s) return '';
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function truncate(s, max) {
  if (s.length <= max) return s;
  return s.slice(0, max - 3) + '...';
}

function repeat(s, n) {
  var result = '';
  for (var i = 0; i < n; i++) result += s;
  return result;
}

module.exports = { capitalize, slugify, truncate, repeat };
