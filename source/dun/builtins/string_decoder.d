module dun.builtins.string_decoder;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerStringDecoderModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerStringDecoderModule");

    auto global = engine.getGlobal();

    auto src = stringDecoderSource();
    auto result = engine.eval(src, "<string_decoder>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("string_decoder init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }

    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in string_decoder registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:string_decoder", &stringDecoderModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "StringDecoder");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int stringDecoderModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_string_decoder__");
        auto sdClass = JS_GetPropertyStr(ctx, mod, "StringDecoder");
        JS_SetModuleExport(ctx, m, "StringDecoder", sdClass);
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string stringDecoderSource() pure @safe nothrow
{
    return `(function() {
  function StringDecoder(encoding) {
    this.encoding = (encoding || 'utf-8').toLowerCase();
    if (this.encoding === 'utf8') this.encoding = 'utf-8';
    this._buffer = [];
    this._needed = 0;
    this._incomplete = [];
  }

  StringDecoder.prototype.write = function(buf) {
    if (!buf || buf.length === 0) return '';

    // Convert various buffer types to array of bytes
    var bytes;
    if (buf instanceof Uint8Array) {
      bytes = buf;
    } else if (Array.isArray(buf)) {
      bytes = new Uint8Array(buf);
    } else if (typeof buf === 'object' && buf.type === 'Buffer' && Array.isArray(buf.data)) {
      bytes = new Uint8Array(buf.data);
    } else {
      return String(buf);
    }

    if (this.encoding === 'utf-8') {
      return this._writeUtf8(bytes);
    }
    // For ascii/latin1, direct byte-to-char mapping
    var result = '';
    for (var i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  };

  StringDecoder.prototype._writeUtf8 = function(bytes) {
    var result = '';
    var i = 0;
    var pending = this._incomplete;

    // If we have incomplete bytes from previous write, prepend them
    if (pending.length > 0) {
      var combined = new Uint8Array(pending.length + bytes.length);
      for (var pi = 0; pi < pending.length; pi++) combined[pi] = pending[pi];
      for (var bi = 0; bi < bytes.length; bi++) combined[pending.length + bi] = bytes[bi];
      bytes = combined;
      this._incomplete = [];
    }

    while (i < bytes.length) {
      var b = bytes[i];
      var needed;
      if (b < 0x80) { needed = 1; }
      else if ((b & 0xE0) === 0xC0) { needed = 2; }
      else if ((b & 0xF0) === 0xE0) { needed = 3; }
      else if ((b & 0xF8) === 0xF0) { needed = 4; }
      else { result += '�'; i++; continue; }

      if (i + needed > bytes.length) {
        // Incomplete multi-byte character; store remainder
        this._incomplete = [];
        for (var ri = i; ri < bytes.length; ri++) this._incomplete.push(bytes[ri]);
        break;
      }

      if (needed === 1) {
        result += String.fromCharCode(b);
      } else if (needed === 2) {
        var cp2 = ((b & 0x1F) << 6) | (bytes[i+1] & 0x3F);
        result += String.fromCharCode(cp2);
      } else if (needed === 3) {
        var cp3 = ((b & 0x0F) << 12) | ((bytes[i+1] & 0x3F) << 6) | (bytes[i+2] & 0x3F);
        result += String.fromCharCode(cp3);
      } else if (needed === 4) {
        var cp4 = ((b & 0x07) << 18) | ((bytes[i+1] & 0x3F) << 12) |
                  ((bytes[i+2] & 0x3F) << 6) | (bytes[i+3] & 0x3F);
        // Surrogate pair for code points above U+FFFF
        if (cp4 > 0xFFFF) {
          cp4 -= 0x10000;
          result += String.fromCharCode(0xD800 + (cp4 >> 10), 0xDC00 + (cp4 & 0x3FF));
        } else {
          result += String.fromCharCode(cp4);
        }
      }
      i += needed;
    }
    return result;
  };

  StringDecoder.prototype.end = function(buf) {
    var result = '';
    if (buf) result = this.write(buf);
    // Flush any incomplete bytes as replacement characters
    if (this._incomplete.length > 0) {
      result += '�';
      this._incomplete = [];
    }
    return result;
  };

  var mod = { StringDecoder: StringDecoder };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_string_decoder__ = mod;
  }
})();`;
}
