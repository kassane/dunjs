module dun.builtins.stream;

import dun.engine.iface : IJSEngine;

void registerStreamModule(IJSEngine engine) @trusted
{
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
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:stream", &streamModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "Readable");
        JS_AddModuleExport(ctx, m, "Writable");
        JS_AddModuleExport(ctx, m, "Duplex");
        JS_AddModuleExport(ctx, m, "Transform");
        JS_AddModuleExport(ctx, m, "PassThrough");
        JS_AddModuleExport(ctx, m, "pipeline");
        JS_AddModuleExport(ctx, m, "finished");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int streamModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_stream__");

        auto readable = JS_GetPropertyStr(ctx, mod, "Readable");
        auto writable = JS_GetPropertyStr(ctx, mod, "Writable");
        auto duplex = JS_GetPropertyStr(ctx, mod, "Duplex");
        auto transform = JS_GetPropertyStr(ctx, mod, "Transform");
        auto passthrough = JS_GetPropertyStr(ctx, mod, "PassThrough");
        auto pl = JS_GetPropertyStr(ctx, mod, "pipeline");
        auto fin = JS_GetPropertyStr(ctx, mod, "finished");

        JS_SetModuleExport(ctx, m, "Readable", JS_DupValue(ctx, readable));
        JS_SetModuleExport(ctx, m, "Writable", JS_DupValue(ctx, writable));
        JS_SetModuleExport(ctx, m, "Duplex", JS_DupValue(ctx, duplex));
        JS_SetModuleExport(ctx, m, "Transform", JS_DupValue(ctx, transform));
        JS_SetModuleExport(ctx, m, "PassThrough", JS_DupValue(ctx, passthrough));
        JS_SetModuleExport(ctx, m, "pipeline", JS_DupValue(ctx, pl));
        JS_SetModuleExport(ctx, m, "finished", JS_DupValue(ctx, fin));
        JS_SetModuleExport(ctx, m, "default", mod);

        JS_FreeValue(ctx, fin);
        JS_FreeValue(ctx, pl);
        JS_FreeValue(ctx, passthrough);
        JS_FreeValue(ctx, transform);
        JS_FreeValue(ctx, duplex);
        JS_FreeValue(ctx, writable);
        JS_FreeValue(ctx, readable);
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
      if (this._buffer.length === 0) {
        this.emit('end');
        if (!this._closed) { this._closed = true; this.emit('close'); }
      }
      return false;
    }
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
    this._flowing = true;

    // Flush buffered data first
    while (this._buffer.length > 0) {
      dest.write(this._buffer.shift());
    }

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

    this.once('end', function() {
      dest.end();
    });

    this.once('error', function(err) {
      dest.destroy(err);
    });

    return dest;
  };

  Readable.prototype.unpipe = function(dest) {
    this.removeAllListeners('data');
    this._flowing = false;
    return this;
  };

  Readable.prototype.resume = function() {
    this._flowing = true;
    while (this._buffer.length > 0) {
      this.emit('data', this._buffer.shift());
    }
    if (this._ended) {
      this.emit('end');
      if (!this._closed) { this._closed = true; this.emit('close'); }
    }
    return this;
  };

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

    var errorOccurred = false;

    function onError(err) {
      if (errorOccurred) return;
      errorOccurred = true;
      for (var k = 0; k < streams.length; k++) {
        if (typeof streams[k].destroy === 'function') streams[k].destroy();
      }
      if (callback) callback(err);
    }

    for (var s = 0; s < streams.length - 1; s++) {
      streams[s].on('error', onError);
      streams[s].pipe(streams[s + 1]);
    }

    var last = streams[streams.length - 1];
    last.on('error', onError);
    last.on('finish', function() {
      if (!errorOccurred && callback) callback(null);
    });
    last.on('end', function() {
      if (!errorOccurred && callback) callback(null);
    });

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

  var mod = {
    Readable: Readable,
    Writable: Writable,
    Duplex: Duplex,
    Transform: Transform,
    PassThrough: PassThrough,
    pipeline: pipeline,
    finished: finished
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_stream__ = mod;
  }
})();`;
}
