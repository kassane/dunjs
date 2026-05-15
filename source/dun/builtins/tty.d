module dun.builtins.tty;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerTtyModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerTtyModule");

    auto result = engine.eval(ttySource(), "<tty>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("tty init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
    else
        engine.freeValue(result.value);

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
        auto m = JS_NewCModule(ctx, "dun:tty", &ttyModuleInit);
        if (m is null) return;
        foreach (name; ["isatty", "ReadStream", "WriteStream", "default"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int ttyModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null);
        assert(m !is null);
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_tty__");
        foreach (name; ["isatty", "ReadStream", "WriteStream"])
        {
            auto fn = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string ttySource() pure @safe nothrow
{
    return `(function() {
  function isatty(fd) {
    if (fd === 0) return !!process.stdin.isTTY;
    if (fd === 1) return !!process.stdout.isTTY;
    if (fd === 2) return !!process.stderr.isTTY;
    return false;
  }

  function ReadStream(fd) {
    if (!(this instanceof ReadStream)) return new ReadStream(fd);
    this.fd = fd;
    this.isTTY = isatty(fd);
    this.isRaw = false;
  }
  ReadStream.prototype.setRawMode = function(mode) {
    this.isRaw = !!mode;
    return this;
  };

  function WriteStream(fd) {
    if (!(this instanceof WriteStream)) return new WriteStream(fd);
    this.fd = fd;
    this.isTTY = isatty(fd);
    this.columns = (typeof process !== 'undefined' && process.stdout) ? process.stdout.columns || 80 : 80;
    this.rows = (typeof process !== 'undefined' && process.stdout) ? process.stdout.rows || 24 : 24;
  }
  WriteStream.prototype.clearLine = function(dir, callback) {
    if (callback) callback();
  };
  WriteStream.prototype.cursorTo = function(x, y, callback) {
    if (typeof y === 'function') { callback = y; y = undefined; }
    if (callback) callback();
  };
  WriteStream.prototype.moveCursor = function(dx, dy, callback) {
    if (callback) callback();
  };
  WriteStream.prototype.getWindowSize = function() {
    return [this.columns, this.rows];
  };
  WriteStream.prototype.hasColors = function(count) {
    if (!this.isTTY) return false;
    if (count === undefined || count <= 256) return true;
    return false;
  };
  WriteStream.prototype.getColorDepth = function() {
    return this.isTTY ? 8 : 1;
  };

  var mod = {
    isatty: isatty,
    ReadStream: ReadStream,
    WriteStream: WriteStream
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_tty__ = mod;
  }
})();`;
}
