// Real-world: Event emitter pattern with async handlers, timers, and microtask ordering

// Minimal EventEmitter implementation
function EventEmitter() {
  this._handlers = {};
}

EventEmitter.prototype.on = function(event, handler) {
  if (!this._handlers[event]) this._handlers[event] = [];
  this._handlers[event].push(handler);
  return this;
};

EventEmitter.prototype.emit = function(event) {
  var args = [];
  for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
  var handlers = this._handlers[event] || [];
  for (var j = 0; j < handlers.length; j++) {
    handlers[j].apply(null, args);
  }
  return handlers.length > 0;
};

EventEmitter.prototype.once = function(event, handler) {
  var self = this;
  function wrapper() {
    var args = [];
    for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
    self.removeListener(event, wrapper);
    handler.apply(null, args);
  }
  return this.on(event, wrapper);
};

EventEmitter.prototype.removeListener = function(event, handler) {
  var handlers = this._handlers[event] || [];
  this._handlers[event] = handlers.filter(function(h) { return h !== handler; });
  return this;
};

// Test the event system
var emitter = new EventEmitter();
var log = [];

// Register handlers
emitter.on('data', function(chunk) {
  log.push('data: ' + chunk);
});

emitter.on('data', function(chunk) {
  log.push('data2: ' + chunk.toUpperCase());
});

emitter.once('end', function() {
  log.push('end (once)');
});

// Simulate a data stream using microtask scheduling
var chunks = ['hello', 'world', 'foo'];
var idx = 0;

function processNext() {
  if (idx < chunks.length) {
    var chunk = chunks[idx++];
    emitter.emit('data', chunk);
    queueMicrotask(processNext);
  } else {
    emitter.emit('end');
    // Try emitting end again — once handler should not fire twice
    emitter.emit('end');
    // Print results after all microtasks
    queueMicrotask(function() {
      log.forEach(function(l) { console.log(l); });
      console.log('total events: ' + log.length);
    });
  }
}

queueMicrotask(processNext);
