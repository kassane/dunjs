// Enhanced DNS module tests
var passed = 0;
var total = 0;

function check(label, condition) {
  total++;
  if (condition) { passed++; console.log('PASS: ' + label); }
  else { console.log('FAIL: ' + label); }
}

var dns = require('dns');

// Existing methods
check('dns.lookup is function', typeof dns.lookup === 'function');
check('dns.lookupSync is function', typeof dns.lookupSync === 'function');
check('dns.resolve4 is function', typeof dns.resolve4 === 'function');
check('dns.resolve6 is function', typeof dns.resolve6 === 'function');

// New: resolve
check('dns.resolve is function', typeof dns.resolve === 'function');

// New: getServers
check('dns.getServers is function', typeof dns.getServers === 'function');
var servers = dns.getServers();
check('getServers returns array', Array.isArray(servers));

// New: dns.promises
check('dns.promises exists', typeof dns.promises === 'object');
check('dns.promises.lookup is function', typeof dns.promises.lookup === 'function');
check('dns.promises.resolve4 is function', typeof dns.promises.resolve4 === 'function');
check('dns.promises.resolve6 is function', typeof dns.promises.resolve6 === 'function');
check('dns.promises.resolve is function', typeof dns.promises.resolve === 'function');

// lookupSync localhost
var result = dns.lookupSync('localhost');
check('lookupSync localhost returns object', typeof result === 'object');
check('lookupSync has address', typeof result.address === 'string');
check('lookupSync has family', typeof result.family === 'number');

// resolve with callback
dns.resolve('localhost', function(err, addresses) {
  check('resolve callback called', true);
  if (!err) {
    check('resolve returns array', Array.isArray(addresses));
  } else {
    check('resolve returns array', false);
  }

  // resolve with rrtype
  dns.resolve('localhost', 'A', function(err2, addrs2) {
    check('resolve A callback called', true);

    console.log('\n' + passed + '/' + total + ' dns checks passed');
  });
});
