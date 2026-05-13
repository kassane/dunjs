// Real-world: Promise-based concurrent task pool with limit
function PromisePool(concurrency) {
  this.concurrency = concurrency;
  this.running = 0;
  this.queue = [];
  this.results = [];
}

PromisePool.prototype.add = function(taskFn) {
  var self = this;
  return new Promise(function(resolve) {
    self.queue.push({ fn: taskFn, resolve: resolve });
    self._drain();
  });
};

PromisePool.prototype._drain = function() {
  var self = this;
  while (self.running < self.concurrency && self.queue.length > 0) {
    var task = self.queue.shift();
    self.running++;
    Promise.resolve().then(function() {
      return task.fn();
    }).then(function(result) {
      self.results.push(result);
      self.running--;
      task.resolve(result);
      self._drain();
    }).catch(function(err) {
      self.results.push('ERROR: ' + err.message);
      self.running--;
      task.resolve(null);
      self._drain();
    });
  }
};

// Simulate async work
function asyncCompute(label, value) {
  return function() {
    return new Promise(function(resolve) {
      queueMicrotask(function() {
        resolve(label + '=' + value);
      });
    });
  };
}

function asyncFail(label) {
  return function() {
    return new Promise(function(_, reject) {
      queueMicrotask(function() {
        reject(new Error(label + ' failed'));
      });
    });
  };
}

// Run pool with concurrency of 2
var pool = new PromisePool(2);

Promise.all([
  pool.add(asyncCompute('a', 1)),
  pool.add(asyncCompute('b', 2)),
  pool.add(asyncFail('c')),
  pool.add(asyncCompute('d', 4)),
  pool.add(asyncCompute('e', 5)),
]).then(function() {
  // Sort results for deterministic output
  pool.results.sort();
  pool.results.forEach(function(r) { console.log(r); });
  console.log('total: ' + pool.results.length);
});
