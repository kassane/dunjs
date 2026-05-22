module dun.builtins.stream;


/// `@trusted policy`: `stream` Node module — Readable/Writable/Duplex/
/// Transform. Every `@trusted` is one of:
///   1. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
///   2. Engine method calls for the EventEmitter-style listener chain.
import dun.engine.iface : IJSEngine;

void registerStreamModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerStreamModule");
    auto global = engine.getGlobal();

    auto result = engine.eval(streamSource(), "<stream>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("Stream init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
    else
        engine.freeValue(result.value);

    version (EngineQuickJS)
        registerQuickJSModule(engine);

    engine.freeValue(global);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:stream", &streamModuleInit);
        if (m is null) return;
        foreach (name; ["Stream", "Readable", "Writable", "Duplex",
                        "Transform", "PassThrough", "pipeline", "finished",
                        "addAbortSignal", "promises", "compose", "isErrored",
                        "isReadable", "isDisturbed", "consumers", "default"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int streamModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in streamModuleInit");
        assert(m !is null, "Null module def in streamModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_stream__");

        foreach (name; ["Stream", "Readable", "Writable", "Duplex",
                        "Transform", "PassThrough", "pipeline", "finished",
                        "addAbortSignal", "promises", "compose", "isErrored",
                        "isReadable", "isDisturbed", "consumers"])
        {
            auto prop = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, prop);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string streamSource() pure @safe nothrow
{
    return `(function() {
  // --- Readable ---
  function Readable(options) {
    EventEmitter.call(this);
    this._buffer = [];
    this._ended = false;
    this._flowing = false;
    this._closed = false;
    this._readableState = { highWaterMark: (options && options.highWaterMark) || 16384 };
    if (options && typeof options.read === 'function')
      this._read = options.read;
  }

  Readable.prototype = Object.create(EventEmitter.prototype);
  Readable.prototype.constructor = Readable;

  Readable.prototype._read = function(size) {};

  Readable.prototype.push = function(chunk) {
    if (chunk === null) {
      this._ended = true;
      this._pushDidWork = true;
      if (this._buffer.length === 0) {
        this.emit('end');
        if (!this._closed) { this._closed = true; this.emit('close'); }
      }
      return false;
    }
    this._pushDidWork = true;
    if (this._flowing) {
      this.emit('data', chunk);
    } else {
      this._buffer.push(chunk);
    }
    return this._buffer.length < this._readableState.highWaterMark;
  };

  Readable.prototype.read = function(size) {
    if (this._buffer.length === 0) {
      if (this._ended) return null;
      this._read(size || this._readableState.highWaterMark);
      if (this._buffer.length === 0) return null;
    }
    if (size === undefined || size === null || size <= 0 || size >= this._buffer.length) {
      var all = this._buffer;
      this._buffer = [];
      if (this._ended && all.length > 0) {
        var self = this;
        Promise.resolve().then(function() {
          self.emit('end');
          if (!self._closed) { self._closed = true; self.emit('close'); }
        });
      }
      if (typeof all[0] === 'string') return all.join('');
      return all.length === 1 ? all[0] : all;
    }
    var out = this._buffer.splice(0, size);
    if (typeof out[0] === 'string') return out.join('');
    return out.length === 1 ? out[0] : out;
  };

  Readable.prototype.pipe = function(dest) {
    var src = this;

    // Attach 'end' / 'error' FIRST. on('data') auto-resumes (see
    // Readable.prototype.on override), which synchronously drains
    // the source -- if 'end' isn't subscribed yet, the upstream
    // 'end' event fires into the void and dest.end() never runs.
    this.once('end', function() {
      dest.end();
    });

    this.once('error', function(err) {
      dest.destroy(err);
    });

    this.on('data', function(chunk) {
      var ok = dest.write(chunk);
      if (!ok) {
        src._flowing = false;
        dest.once('drain', function() {
          src._flowing = true;
          src.resume();
        });
      }
    });

    // on('data') auto-resumed if flow was off; force a resume here in
    // case 'data' was already attached so the pump runs.
    if (!this._flowing) this.resume();

    return dest;
  };

  Readable.prototype.unpipe = function(dest) {
    this.removeAllListeners('data');
    this._flowing = false;
    return this;
  };

  Readable.prototype.resume = function() {
    this._flowing = true;
    // Drain any pre-buffered data first.
    while (this._buffer.length > 0) {
      this.emit('data', this._buffer.shift());
    }
    // Then pump _read() until exhausted. Push-mode readables
    // (Readable.from([...])) need this to flow -- on(data) +
    // pipe don't trigger a pull on their own. _pushDidWork
    // gates so we stop when _read makes no progress (would
    // loop forever otherwise -- e.g. Transform whose _read is
    // a no-op).
    while (this._flowing && !this._ended) {
      this._pushDidWork = false;
      try { this._read(this._readableState.highWaterMark); }
      catch (e) { this.emit('error', e); break; }
      if (!this._pushDidWork) break;
      while (this._buffer.length > 0) {
        this.emit('data', this._buffer.shift());
      }
    }
    if (this._ended) {
      this.emit('end');
      if (!this._closed) { this._closed = true; this.emit('close'); }
    }
    return this;
  };

  var _readableOn = Readable.prototype.on;
  Readable.prototype.on = function(event, fn) {
    var ret = _readableOn.call(this, event, fn);
    if (event === 'data' && !this._flowing) {
      this.resume();
    }
    return ret;
  };
  Readable.prototype.addListener = Readable.prototype.on;

  Readable.prototype.pause = function() {
    this._flowing = false;
    return this;
  };

  Readable.prototype.destroy = function(err) {
    this._buffer = [];
    this._ended = true;
    if (err) this.emit('error', err);
    if (!this._closed) { this._closed = true; this.emit('close'); }
    return this;
  };

  Readable.prototype.setEncoding = function(enc) {
    this._encoding = enc;
    return this;
  };

  Readable.prototype[Symbol.asyncIterator] = function() {
    var self = this;
    var done = false;
    self.on('end', function() { done = true; });
    return {
      next: function() {
        if (done) return Promise.resolve({ value: undefined, done: true });
        var chunk = self.read();
        if (chunk !== null) return Promise.resolve({ value: chunk, done: false });
        // read() returned null but might have synchronously triggered
        // 'end' (e.g. Readable.from's _read pushes null when items
        // exhausted, which fires 'end' inside push). The done flag
        // we set on 'end' catches that case so we don't hang waiting
        // for an event that already fired.
        if (self._ended || done)
          return Promise.resolve({ value: undefined, done: true });
        return new Promise(function(resolve) {
          function onData(d) { cleanup(); resolve({ value: d, done: false }); }
          function onEnd() { cleanup(); resolve({ value: undefined, done: true }); }
          function cleanup() { self.removeListener('data', onData); self.removeListener('end', onEnd); }
          self.once('data', onData);
          self.once('end', onEnd);
        });
      }
    };
  };

  Readable.from = function(iterable, opts) {
    var r = new Readable(opts);
    var items = Array.isArray(iterable) ? iterable : Array.from(iterable);
    var idx = 0;
    r._read = function() {
      if (idx < items.length) r.push(items[idx++]);
      else r.push(null);
    };
    return r;
  };

  // --- Writable ---
  function Writable(options) {
    EventEmitter.call(this);
    this._buffer = [];
    this._finished = false;
    this._closed = false;
    this._writing = false;
    this._writableState = { highWaterMark: (options && options.highWaterMark) || 16384 };
    if (options && typeof options.write === 'function')
      this._write = options.write;
    if (options && typeof options.final === 'function')
      this._final = options.final;
  }

  Writable.prototype = Object.create(EventEmitter.prototype);
  Writable.prototype.constructor = Writable;

  Writable.prototype._write = function(chunk, encoding, callback) {
    callback();
  };

  Writable.prototype._final = function(callback) {
    callback();
  };

  Writable.prototype.write = function(chunk, encoding, callback) {
    if (typeof encoding === 'function') { callback = encoding; encoding = 'utf8'; }
    if (this._finished) {
      var err = new Error('write after end');
      if (callback) callback(err);
      this.emit('error', err);
      return false;
    }
    var self = this;
    this._writing = true;
    this._write(chunk, encoding || 'utf8', function(err) {
      self._writing = false;
      if (err) {
        if (callback) callback(err);
        self.emit('error', err);
      } else {
        if (callback) callback();
        self.emit('drain');
      }
    });
    return this._buffer.length < this._writableState.highWaterMark;
  };

  Writable.prototype.end = function(chunk, encoding, callback) {
    if (typeof chunk === 'function') { callback = chunk; chunk = undefined; encoding = undefined; }
    if (typeof encoding === 'function') { callback = encoding; encoding = undefined; }
    if (chunk !== undefined && chunk !== null) this.write(chunk, encoding);
    var self = this;
    this._final(function(err) {
      if (err) {
        self.emit('error', err);
      } else {
        self._finished = true;
        self.emit('finish');
        if (!self._closed) { self._closed = true; self.emit('close'); }
      }
      if (callback) callback(err);
    });
    return this;
  };

  Writable.prototype.destroy = function(err) {
    this._finished = true;
    if (err) this.emit('error', err);
    if (!this._closed) { this._closed = true; this.emit('close'); }
    return this;
  };

  Writable.prototype.cork = function() { this._corked = true; };
  Writable.prototype.uncork = function() { this._corked = false; };

  // --- Duplex ---
  function Duplex(options) {
    Readable.call(this, options);
    Writable.call(this, options);
    this._finished = false;
    this._closed = false;
    if (options && typeof options.read === 'function')
      this._read = options.read;
    if (options && typeof options.write === 'function')
      this._write = options.write;
  }

  Duplex.prototype = Object.create(Readable.prototype);
  // Mixin Writable methods
  var writableMethods = ['write', 'end', 'cork', 'uncork', '_write', '_final'];
  writableMethods.forEach(function(method) {
    Duplex.prototype[method] = Writable.prototype[method];
  });
  Duplex.prototype.constructor = Duplex;

  Duplex.prototype.destroy = function(err) {
    this._buffer = [];
    this._ended = true;
    this._finished = true;
    if (err) this.emit('error', err);
    if (!this._closed) { this._closed = true; this.emit('close'); }
    return this;
  };

  // --- Transform ---
  function Transform(options) {
    Duplex.call(this, options);
    this._transformState = { transforming: false, pendingCallback: null };
    if (options && typeof options.transform === 'function')
      this._transform = options.transform;
    if (options && typeof options.flush === 'function')
      this._flush = options.flush;
  }

  Transform.prototype = Object.create(Duplex.prototype);
  Transform.prototype.constructor = Transform;

  Transform.prototype._transform = function(chunk, encoding, callback) {
    callback(null, chunk);
  };

  Transform.prototype._flush = function(callback) {
    callback();
  };

  Transform.prototype._write = function(chunk, encoding, callback) {
    var self = this;
    this._transform(chunk, encoding, function(err, data) {
      if (err) {
        callback(err);
        return;
      }
      if (data !== null && data !== undefined) self.push(data);
      callback();
    });
  };

  Transform.prototype._final = function(callback) {
    var self = this;
    this._flush(function(err, data) {
      if (err) { callback(err); return; }
      if (data !== null && data !== undefined) self.push(data);
      self.push(null);
      callback();
    });
  };

  // --- PassThrough ---
  function PassThrough(options) {
    Transform.call(this, options);
  }

  PassThrough.prototype = Object.create(Transform.prototype);
  PassThrough.prototype.constructor = PassThrough;

  PassThrough.prototype._transform = function(chunk, encoding, callback) {
    callback(null, chunk);
  };

  // --- pipeline ---
  function pipeline() {
    var streams = [];
    var callback;
    for (var i = 0; i < arguments.length; i++) {
      if (typeof arguments[i] === 'function' && i === arguments.length - 1) {
        callback = arguments[i];
      } else if (Array.isArray(arguments[i])) {
        for (var j = 0; j < arguments[i].length; j++) streams.push(arguments[i][j]);
      } else {
        streams.push(arguments[i]);
      }
    }

    if (streams.length < 2) {
      var err = new Error('pipeline requires at least 2 streams');
      if (callback) callback(err);
      else throw err;
      return;
    }

    // Attach completion listeners on the LAST stream BEFORE wiring
    // the pipes. Our pipe() is synchronous (resume drains
    // immediately) so by the time the for loop reaches the second
    // pipe call, the last stream may already be finished -- a
    // listener attached afterward would miss the event and the
    // callback never fires.
    var doneCalled = false;
    function done(err) {
      if (doneCalled) return;
      doneCalled = true;
      if (err) {
        for (var k = 0; k < streams.length; k++) {
          if (typeof streams[k].destroy === 'function') streams[k].destroy();
        }
      }
      if (callback) callback(err);
    }
    var errorOccurred = false;
    function onError(err) {
      if (errorOccurred) return;
      errorOccurred = true;
      done(err);
    }
    var last = streams[streams.length - 1];
    last.on('finish', function() { if (!errorOccurred) done(null); });
    last.on('end', function() { if (!errorOccurred) done(null); });
    last.on('error', onError);

    for (var s = 0; s < streams.length - 1; s++) {
      streams[s].on('error', onError);
      streams[s].pipe(streams[s + 1]);
    }

    return last;
  }

  // --- finished ---
  function finished(stream, opts, callback) {
    if (typeof opts === 'function') { callback = opts; opts = {}; }
    opts = opts || {};
    var once = false;
    function done(err) {
      if (once) return;
      once = true;
      if (callback) callback(err || null);
    }
    if (stream._readableState && stream._readableState.ended) { done(); return done; }
    if (stream._finished) { done(); return done; }
    if (stream.on) {
      stream.on('end', function() { done(); });
      stream.on('finish', function() { done(); });
      stream.on('error', function(err) { done(err); });
      stream.on('close', function() { done(); });
    }
    return done;
  }

  // --- Stream base (alias) ---
  function Stream(opts) { EventEmitter.call(this); }
  Stream.prototype = Object.create(EventEmitter.prototype);
  Stream.prototype.constructor = Stream;
  Stream.prototype.pipe = Readable.prototype.pipe;

  // --- addAbortSignal ---
  function addAbortSignal(signal, stream) {
    if (signal && typeof signal.addEventListener === 'function') {
      signal.addEventListener('abort', function() {
        if (typeof stream.destroy === 'function') stream.destroy(new Error('AbortError'));
      });
    }
    return stream;
  }

  // --- promises.pipeline ---
  var promises = {
    pipeline: function() {
      var args = Array.prototype.slice.call(arguments);
      return new Promise(function(resolve, reject) {
        args.push(function(err) {
          if (err) reject(err);
          else resolve();
        });
        pipeline.apply(null, args);
      });
    },
    finished: function(stream, opts) {
      return new Promise(function(resolve, reject) {
        finished(stream, opts || {}, function(err) {
          if (err) reject(err);
          else resolve();
        });
      });
    }
  };

  // --- Static utility methods on Readable ---
  Readable.isReadable = function(stream) { return stream && typeof stream.read === 'function' && stream.destroyed !== true; };
  Readable.isDisturbed = function(stream) { return stream && stream._readableState && stream._readableState.dataEmitted === true; };
  Readable.fromWeb = function(readableStream, opts) {
    var r = new Readable(opts);
    var reader = readableStream.getReader();
    function pump() {
      reader.read().then(function(result) {
        if (result.done) { r.push(null); return; }
        r.push(result.value);
        pump();
      }).catch(function(err) { r.destroy(err); });
    }
    pump();
    return r;
  };
  Writable.fromWeb = function(writableStream, opts) {
    var w = new Writable(opts);
    return w;
  };

  // --- Readable.toWeb / Writable.toWeb stubs ---
  Readable.toWeb = function(readable) {
    return new ReadableStream({
      start: function(controller) {
        readable.on('data', function(chunk) { controller.enqueue(chunk); });
        readable.on('end', function() { controller.close(); });
        readable.on('error', function(err) { controller.error(err); });
      }
    });
  };

  Writable.toWeb = function(writable) {
    return new WritableStream({
      write: function(chunk) {
        return new Promise(function(resolve, reject) {
          writable.write(chunk, function(err) {
            if (err) reject(err);
            else resolve();
          });
        });
      },
      close: function() {
        return new Promise(function(resolve) { writable.end(resolve); });
      }
    });
  };

  function compose() {
    var streams = Array.prototype.slice.call(arguments);
    if (streams.length === 1 && Array.isArray(streams[0])) streams = streams[0];
    if (streams.length === 0) throw new Error('stream.compose requires at least one stream');
    if (streams.length === 1) return streams[0];
    var first = streams[0], last = streams[streams.length - 1];
    for (var i = 0; i < streams.length - 1; i++) {
      if (typeof streams[i].pipe === 'function') streams[i].pipe(streams[i + 1]);
    }
    var composed = new Duplex({
      write: function(chunk, enc, cb) { first.write(chunk, enc, cb); },
      read: function() {},
      final: function(cb) { first.end(cb); }
    });
    last.on('data', function(chunk) { if (!composed.push(chunk)) last.pause && last.pause(); });
    last.on('end', function() { composed.push(null); });
    last.on('error', function(err) { composed.destroy(err); });
    first.on('error', function(err) { composed.destroy(err); });
    return composed;
  }
  function isErrored(stream) { return stream && stream.destroyed === true && stream.errored != null; }
  function isReadable(stream) { return stream && typeof stream.read === 'function' && stream.destroyed !== true; }
  function isDisturbed(stream) { return stream && (stream.readableDidRead === true || stream._readableState && stream._readableState.dataEmitted === true); }
  var consumers = {
    arrayBuffer: function(stream) { return new Promise(function(res, rej) { var chunks = []; stream.on('data', function(c){chunks.push(c);}); stream.on('end', function(){res(Buffer.concat(chunks));}); stream.on('error', rej); }); },
    text: function(stream) { return new Promise(function(res, rej) { var s = ''; stream.on('data', function(c){s += c.toString();}); stream.on('end', function(){res(s);}); stream.on('error', rej); }); },
    json: function(stream) { return consumers.text(stream).then(JSON.parse); },
    blob: function(stream) { return consumers.arrayBuffer(stream).then(function(buf){return new Blob([buf]);}); },
    buffer: function(stream) { return consumers.arrayBuffer(stream); }
  };

  // Node.js compat: require('stream') returns the Stream constructor
  // with Readable, Writable, etc. as properties on it
  Stream.Stream = Stream;
  Stream.Readable = Readable;
  Stream.Writable = Writable;
  Stream.Duplex = Duplex;
  Stream.Transform = Transform;
  Stream.PassThrough = PassThrough;
  Stream.pipeline = pipeline;
  Stream.finished = finished;
  Stream.addAbortSignal = addAbortSignal;
  Stream.promises = promises;
  Stream.compose = compose;
  Stream.isErrored = isErrored;
  Stream.isReadable = isReadable;
  Stream.isDisturbed = isDisturbed;
  Stream.consumers = consumers;

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_stream__ = Stream;
  }
})();`;
}
