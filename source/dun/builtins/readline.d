module dun.builtins.readline;


/// `@trusted policy`: `readline` Node module. Every `@trusted` is one
/// of:
///   1. POSIX `read(STDIN_FILENO)` + termios for line editing.
///   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.builtins.helpers : installPureJsModule;

void registerReadlineModule(IJSEngine engine) @trusted
{
    installPureJsModule(engine, readlineSource(), "<readline>", "readline");

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in readline registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:readline", &readlineModuleInit);
        if (m is null) return;
        foreach (name; ["createInterface", "Interface", "promises", "default"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int readlineModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_readline__");
        foreach (name; ["createInterface", "Interface", "promises"])
        {
            auto val = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, val);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string readlineSource() pure @safe nothrow
{
    return `(function() {
  function Interface(options) {
    if (!(this instanceof Interface)) return new Interface(options);
    var opts = typeof options === 'object' ? options : {};
    this.input = opts.input || (typeof process !== 'undefined' ? process.stdin : null);
    this.output = opts.output || (typeof process !== 'undefined' ? process.stdout : null);
    this.terminal = opts.terminal !== undefined ? opts.terminal : false;
    this.prompt_ = opts.prompt !== undefined ? opts.prompt : '> ';
    this._events = {};
    this._closed = false;
    this._lines = [];
  }

  Interface.prototype.on = function(event, listener) {
    if (!this._events[event]) this._events[event] = [];
    this._events[event].push(listener);
    return this;
  };

  Interface.prototype.once = function(event, listener) {
    var self = this;
    function wrapped() {
      self.removeListener(event, wrapped);
      listener.apply(this, arguments);
    }
    wrapped._original = listener;
    return this.on(event, wrapped);
  };

  Interface.prototype.removeListener = function(event, listener) {
    if (!this._events[event]) return this;
    this._events[event] = this._events[event].filter(function(l) {
      return l !== listener && l._original !== listener;
    });
    return this;
  };

  Interface.prototype.emit = function(event) {
    if (!this._events[event]) return false;
    var args = Array.prototype.slice.call(arguments, 1);
    var listeners = this._events[event].slice();
    for (var i = 0; i < listeners.length; i++) {
      listeners[i].apply(this, args);
    }
    return true;
  };

  Interface.prototype.setPrompt = function(prompt) {
    this.prompt_ = prompt;
  };

  Interface.prototype.prompt = function(preserveCursor) {
    if (this.output && this.output.write) {
      this.output.write(this.prompt_);
    }
  };

  Interface.prototype.question = function(query, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    if (this.output && this.output.write) {
      this.output.write(query);
    }
    if (this.input && this.input.read) {
      var data = this.input.read();
      if (data !== null && data !== undefined) {
        var line = String(data).replace(/[\r\n]+$/, '');
        if (callback) callback(line);
      } else {
        if (callback) callback('');
      }
    } else if (callback) {
      callback('');
    }
  };

  Interface.prototype.close = function() {
    if (this._closed) return;
    this._closed = true;
    this.emit('close');
  };

  Interface.prototype.pause = function() {
    this.emit('pause');
    return this;
  };

  Interface.prototype.resume = function() {
    this.emit('resume');
    return this;
  };

  Interface.prototype.write = function(data) {
    if (data !== null && data !== undefined) {
      var lines = String(data).split(/\r?\n/);
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].length > 0 || i < lines.length - 1) {
          this.emit('line', lines[i]);
        }
      }
    }
    return this;
  };

  Interface.prototype[Symbol.asyncIterator] = function() {
    var self = this;
    var done = false;
    self.on('close', function() { done = true; });
    return {
      next: function() {
        if (done) return Promise.resolve({ value: undefined, done: true });
        return new Promise(function(resolve) {
          self.once('line', function(line) {
            resolve({ value: line, done: false });
          });
          self.once('close', function() {
            resolve({ value: undefined, done: true });
          });
        });
      }
    };
  };

  function createInterface(options) {
    if (typeof options === 'object' && options.input) {
      return new Interface(options);
    }
    return new Interface({ input: options });
  }

  var mod = {
    createInterface: createInterface,
    Interface: Interface,
    promises: {
      createInterface: function(opts) {
        var rl = createInterface(opts);
        rl[Symbol.asyncIterator] = function() { return rl[Symbol.asyncIterator](); };
        return rl;
      }
    }
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_readline__ = mod;
  }
})();`;
}
