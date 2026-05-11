// Validator that depends on string_utils
var str = require('./string_utils');

function validateUsername(name) {
  if (typeof name !== 'string') return { valid: false, reason: 'not a string' };
  if (name.length < 3) return { valid: false, reason: 'too short' };
  if (name.length > 20) return { valid: false, reason: 'too long' };
  var slug = str.slugify(name);
  if (slug !== name.toLowerCase()) return { valid: false, reason: 'invalid chars' };
  return { valid: true, normalized: slug };
}

function validateEmail(email) {
  if (typeof email !== 'string') return { valid: false, reason: 'not a string' };
  var parts = email.split('@');
  if (parts.length !== 2) return { valid: false, reason: 'missing @' };
  if (parts[0].length === 0) return { valid: false, reason: 'empty local' };
  if (parts[1].indexOf('.') === -1) return { valid: false, reason: 'invalid domain' };
  return { valid: true };
}

module.exports = { validateUsername, validateEmail, stringUtils: str };
