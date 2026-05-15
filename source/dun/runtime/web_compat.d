module dun.runtime.web_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installWebCompat(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installWebCompat");
    auto global = engine.getGlobal();

    // globalThis.global = globalThis — Node.js legacy compat (npm packages check typeof global)
    engine.setProperty(global, "global", engine.dupValue(global));

    auto scRes = engine.eval(structuredClonePolyfill(), "<structuredClone>");
    if (!scRes.isError)
        engine.freeValue(scRes.value);

    engine.setProperty(global, "btoa",
        engine.newFunction(&jsNativeBtoa, "btoa", 1));
    engine.setProperty(global, "atob",
        engine.newFunction(&jsNativeAtob, "atob", 1));

    // TextEncoder/TextDecoder — register constructors via eval, then bind
    // native D functions directly on prototypes (no JS wrapper indirection).
    auto teRes = engine.eval(textEncoderSetup(), "<web-compat>");
    if (!teRes.isError)
        engine.freeValue(teRes.value);

    auto teCtor = engine.getProperty(global, "TextEncoder");
    auto teProto = engine.getProperty(teCtor, "prototype");
    engine.setProperty(teProto, "encode",
        engine.newFunction(&jsNativeTextEncoderEncode, "encode", 1));
    engine.setProperty(teProto, "encodeInto",
        engine.newFunction(&jsNativeTextEncoderEncodeInto, "encodeInto", 2));
    engine.freeValue(teProto);
    engine.freeValue(teCtor);

    auto tdCtor = engine.getProperty(global, "TextDecoder");
    auto tdProto = engine.getProperty(tdCtor, "prototype");
    engine.setProperty(tdProto, "decode",
        engine.newFunction(&jsNativeTextDecoderDecode, "decode", 1));
    engine.freeValue(tdProto);
    engine.freeValue(tdCtor);

    // Error.captureStackTrace + Error.stackTraceLimit (V8/Node compat)
    auto errRes = engine.eval(errorCapturePolyfill(), "<error-compat>");
    if (!errRes.isError)
        engine.freeValue(errRes.value);

    engine.freeValue(global);
}

private string errorCapturePolyfill() pure nothrow @safe
{
    return
        "(function(){"
        // CallSite shim for V8's structured stack trace API
        ~ "function CallSite(fn,file,line,col){"
        ~   "this._fn=fn||'';this._file=file||'<anonymous>';this._line=line||0;this._col=col||0;"
        ~ "}"
        ~ "CallSite.prototype.getFileName=function(){return this._file;};"
        ~ "CallSite.prototype.getLineNumber=function(){return this._line;};"
        ~ "CallSite.prototype.getColumnNumber=function(){return this._col;};"
        ~ "CallSite.prototype.getFunctionName=function(){return this._fn||null;};"
        ~ "CallSite.prototype.getTypeName=function(){return null;};"
        ~ "CallSite.prototype.getMethodName=function(){return this._fn||null;};"
        ~ "CallSite.prototype.isEval=function(){return false;};"
        ~ "CallSite.prototype.isNative=function(){return false;};"
        ~ "CallSite.prototype.isConstructor=function(){return false;};"
        ~ "CallSite.prototype.isToplevel=function(){return true;};"
        ~ "CallSite.prototype.toString=function(){"
        ~   "var s=this._fn?this._fn:'<anonymous>';"
        ~   "return s+' ('+this._file+':'+this._line+':'+this._col+')';"
        ~ "};"

        ~ "function parseStack(stack){"
        ~   "if(!stack)return[new CallSite('','<anonymous>',0,0)];"
        ~   "var lines=stack.split('\\n');"
        ~   "var sites=[];"
        ~   "for(var i=0;i<lines.length;i++){"
        ~     "var line=lines[i].trim();"
        ~     "if(!line)continue;"
        // V8/QuickJS: "    at funcName (file:line:col)" or "    at file:line"
        ~     "var m=line.match(/at\\s+(?:(.+?)\\s+)?\\(?(.+?):(\\d+)(?::(\\d+))?\\)?$/);"
        ~     "if(m){sites.push(new CallSite(m[1]||'',m[2]||'',parseInt(m[3])||0,parseInt(m[4])||0));}"
        // JSC/Safari: "funcName@file:line:col" or "global code@file:line:col"
        ~     "else{m=line.match(/^(.+?)@(.+?):(\\d+)(?::(\\d+))?$/);"
        ~       "if(m){var fn=m[1]==='global code'?'':m[1];sites.push(new CallSite(fn,m[2]||'',parseInt(m[3])||0,parseInt(m[4])||0));}"
        ~       "else if(line.indexOf('at ')!==-1)sites.push(new CallSite('',line.replace(/^\\s*at\\s*/,''),0,0));"
        ~     "}"
        ~   "}"
        ~   "if(sites.length===0)sites.push(new CallSite('','<anonymous>',0,0));"
        ~   "return sites;"
        ~ "}"

        // Augment CallSite objects with missing V8 methods
        ~ "function augmentSite(s){"
        ~   "if(!s.isEval)s.isEval=function(){return false;};"
        ~   "if(!s.isConstructor)s.isConstructor=function(){return false;};"
        ~   "if(!s.isToplevel)s.isToplevel=function(){return true;};"
        ~   "if(!s.getTypeName)s.getTypeName=function(){return null;};"
        ~   "if(!s.getMethodName)s.getMethodName=function(){return(s.getFunctionName&&s.getFunctionName())||null;};"
        ~   "if(!s.getEvalOrigin)s.getEvalOrigin=function(){return'';};"
        ~   "return s;"
        ~ "}"

        // Detect if native captureStackTrace supports prepareStackTrace (V8/QuickJS do, JSC doesn't)
        ~ "var _needsPolyfill=true;"
        ~ "if(Error.captureStackTrace){"
        ~   "var _cstProto=null;var _pstCalled=false;"
        ~   "var _origPST=Error.prepareStackTrace;"
        ~   "Error.prepareStackTrace=function(o,s){_pstCalled=true;_cstProto=s.length?Object.getPrototypeOf(s[0]):null;return s;};"
        ~   "try{var _t={};Error.captureStackTrace(_t);var _s=_t.stack;}catch(e){}"
        ~   "Error.prepareStackTrace=_origPST;"
        ~   "if(_pstCalled&&_cstProto){"
        ~     "_needsPolyfill=false;"
        ~     "if(!_cstProto.isEval)_cstProto.isEval=function(){return false;};"
        ~     "if(!_cstProto.isConstructor)_cstProto.isConstructor=function(){return false;};"
        ~     "if(!_cstProto.isToplevel)_cstProto.isToplevel=function(){return true;};"
        ~     "if(!_cstProto.getTypeName)_cstProto.getTypeName=function(){return null;};"
        ~     "if(!_cstProto.getMethodName)_cstProto.getMethodName=function(){return this.getFunctionName?this.getFunctionName():null;};"
        ~     "if(!_cstProto.getEvalOrigin)_cstProto.getEvalOrigin=function(){return'';};"
        ~     "if(!_cstProto.getThis)_cstProto.getThis=function(){return undefined;};"
        ~   "}"
        ~ "}"
        ~ "if(_needsPolyfill){"
        ~   "Error.captureStackTrace=function(obj,ctor){"
        ~     "var stackStr=(new Error()).stack||'';"
        ~     "Object.defineProperty(obj,'stack',{"
        ~       "get:function(){"
        ~         "if(Error.prepareStackTrace){"
        ~           "var sites=parseStack(stackStr).map(augmentSite);"
        ~           "return Error.prepareStackTrace(obj,sites);"
        ~         "}"
        ~         "return stackStr;"
        ~       "},configurable:true"
        ~     "});"
        ~   "};"
        ~ "}"
        ~ "if(Error.stackTraceLimit===undefined)Error.stackTraceLimit=10;"

        // Patch Error stack to include "ErrorName: message" prefix (QuickJS only)
        // V8/JSC already format stacks with prefix; QuickJS starts with "    at ..."
        ~ "(function(){"
        ~   "var testStack=(new Error('x')).stack||'';"
        ~   "if(testStack.indexOf('Error')===0)return;"
        ~   "function _fixStack(err){"
        ~     "var raw=err.stack;"
        ~     "if(typeof raw==='string'&&raw.length>0&&raw.charAt(0)===' '){"
        ~       "var prefix=(err.name||'Error');"
        ~       "if(err.message)prefix+=': '+err.message;"
        ~       "Object.defineProperty(err,'stack',{value:prefix+'\\n'+raw,writable:true,configurable:true,enumerable:false});"
        ~     "}"
        ~   "}"
        ~   "['Error','TypeError','RangeError','ReferenceError','SyntaxError','URIError','EvalError'].forEach(function(name){"
        ~     "var Orig=globalThis[name];"
        ~     "if(!Orig)return;"
        ~     "globalThis[name]=function(){"
        ~       "var inst=new(Function.prototype.bind.apply(Orig,[null].concat(Array.from(arguments))));"
        ~       "_fixStack(inst);"
        ~       "return inst;"
        ~     "};"
        ~     "globalThis[name].prototype=Orig.prototype;"
        ~     "globalThis[name].prototype.constructor=globalThis[name];"
        ~     "Object.setPrototypeOf(globalThis[name],Orig);"
        ~     "Object.defineProperty(globalThis[name],'name',{value:name});"
        ~   "});"
        ~ "})()"

        ~ "})();";
}

private string textEncoderSetup() pure nothrow @safe
{
    return
    "(function(){"
    ~ "globalThis.TextEncoder=function TextEncoder(){this.encoding='utf-8';};"
    ~ "globalThis.TextDecoder=function TextDecoder(l){this.encoding=l||'utf-8';};"
    ~ "})();";
}


private:

// CTFE base64 tables
enum B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
enum ubyte[128] B64_DECODE = () {
    ubyte[128] t = 0xFF;
    foreach (i, c; B64_CHARS)
        t[c] = cast(ubyte) i;
    return t;
}();

JSHandle jsNativeBtoa(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in btoa");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in btoa");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("");

    auto input = engine.extractString(args[0]);
    if (input.length == 0) return engine.newString("");

    auto len = input.length;
    auto outLen = ((len + 2) / 3) * 4;
    enum STACK_LIMIT = 4096;
    char[STACK_LIMIT] stackBuf = void;
    char[] buf;
    if (outLen <= STACK_LIMIT)
        buf = stackBuf[0 .. outLen];
    else
        buf = new char[outLen];
    size_t pos = 0;
    size_t i = 0;

    while (i + 2 < len)
    {
        uint a = cast(ubyte) input[i++];
        uint b = cast(ubyte) input[i++];
        uint c = cast(ubyte) input[i++];
        uint n = (a << 16) | (b << 8) | c;
        buf[pos++] = B64_CHARS[(n >> 18) & 63];
        buf[pos++] = B64_CHARS[(n >> 12) & 63];
        buf[pos++] = B64_CHARS[(n >> 6) & 63];
        buf[pos++] = B64_CHARS[n & 63];
    }
    auto rem = len - i;
    if (rem == 1)
    {
        uint a = cast(ubyte) input[i];
        buf[pos++] = B64_CHARS[(a >> 2) & 63];
        buf[pos++] = B64_CHARS[(a << 4) & 63];
        buf[pos++] = '=';
        buf[pos++] = '=';
    }
    else if (rem == 2)
    {
        uint a = cast(ubyte) input[i];
        uint b = cast(ubyte) input[i + 1];
        buf[pos++] = B64_CHARS[(a >> 2) & 63];
        buf[pos++] = B64_CHARS[((a << 4) | (b >> 4)) & 63];
        buf[pos++] = B64_CHARS[(b << 2) & 63];
        buf[pos++] = '=';
    }

    return engine.newString(cast(string) buf[0 .. pos]);
}

JSHandle jsNativeAtob(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in atob");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in atob");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("");

    auto input = engine.extractString(args[0]);
    auto len = input.length;
    while (len > 0 && input[len - 1] == '=') len--;
    if (len == 0) return engine.newString("");

    auto outLen = (len * 3) / 4;
    enum STACK_LIMIT = 4096;
    char[STACK_LIMIT] stackBuf = void;
    char[] buf;
    if (outLen <= STACK_LIMIT)
        buf = stackBuf[0 .. outLen];
    else
        buf = new char[outLen];
    size_t pos = 0;
    size_t i = 0;

    while (i + 3 < len)
    {
        ubyte a = B64_DECODE[input[i++] & 0x7F];
        ubyte b = B64_DECODE[input[i++] & 0x7F];
        ubyte c = B64_DECODE[input[i++] & 0x7F];
        ubyte d = B64_DECODE[input[i++] & 0x7F];
        buf[pos++] = cast(char)((a << 2) | (b >> 4));
        buf[pos++] = cast(char)(((b & 0xF) << 4) | (c >> 2));
        buf[pos++] = cast(char)(((c & 3) << 6) | d);
    }
    auto rem = len - i;
    if (rem >= 2)
    {
        ubyte a = B64_DECODE[input[i++] & 0x7F];
        ubyte b = B64_DECODE[input[i++] & 0x7F];
        buf[pos++] = cast(char)((a << 2) | (b >> 4));
        if (rem >= 3)
        {
            ubyte c = B64_DECODE[input[i++] & 0x7F];
            buf[pos++] = cast(char)(((b & 0xF) << 4) | (c >> 2));
        }
    }

    return engine.newString(cast(string) buf[0 .. pos]);
}

JSHandle jsNativeTextEncoderEncode(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextEncoder.encode");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextEncoder.encode");
    auto engine = state.engine;

    if (args.length < 1 || engine.isUndefined(args[0]) || engine.isNull(args[0]))
        return engine.newUint8Array(cast(ubyte[]) []);

    auto input = engine.extractString(args[0]);
    if (input.length == 0) return engine.newUint8Array(cast(ubyte[]) []);

    return engine.newUint8Array(cast(const(ubyte)[]) input);
}

JSHandle jsNativeTextEncoderEncodeInto(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextEncoder.encodeInto");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextEncoder.encodeInto");
    auto engine = state.engine;

    if (args.length < 2)
        return engine.throwTypeError("encodeInto requires string and Uint8Array");

    auto input = engine.extractString(args[0]);
    auto destBytes = engine.getTypedArrayBytes(args[1]);
    if (destBytes is null)
        return engine.throwTypeError("encodeInto: second argument must be a Uint8Array");

    auto src = cast(const(ubyte)[]) input;
    auto written = src.length < destBytes.length ? src.length : destBytes.length;
    import core.stdc.string : memcpy;
    if (written > 0)
        memcpy(destBytes.ptr, src.ptr, written);

    auto result = engine.newObject();
    engine.setProperty(result, "read", engine.newInt(cast(int) input.length));
    engine.setProperty(result, "written", engine.newInt(cast(int) written));
    return result;
}

JSHandle jsNativeTextDecoderDecode(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextDecoder.decode");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextDecoder.decode");
    auto engine = state.engine;

    if (args.length < 1 || engine.isUndefined(args[0]) || engine.isNull(args[0]))
        return engine.newString("");

    if (engine.isString(args[0]))
        return engine.dupValue(args[0]);

    auto bytes = engine.getTypedArrayBytes(args[0]);
    if (bytes !is null && bytes.length > 0)
        return engine.newString(cast(const(char)[]) bytes);

    if (engine.isObject(args[0]))
    {
        auto lenVal = engine.getProperty(args[0], "length");
        if (engine.isNumber(lenVal))
        {
            int len = engine.extractInt(lenVal);
            engine.freeValue(lenVal);
            if (len == 0) return engine.newString("");
            auto buf = new ubyte[len];
            foreach (i; 0 .. len)
            {
                auto elem = engine.getPropertyIndex(args[0], cast(uint) i);
                buf[i] = cast(ubyte) engine.extractInt(elem);
                engine.freeValue(elem);
            }
            return engine.newString(cast(const(char)[]) buf);
        }
        engine.freeValue(lenVal);
    }

    return engine.newString("");
}

string structuredClonePolyfill() @safe pure nothrow @nogc
{
    return `(function() {
  globalThis.structuredClone = function structuredClone(value, options) {
    if (value === null || value === undefined) return value;
    var t = typeof value;
    if (t === 'number' || t === 'string' || t === 'boolean' || t === 'bigint') return value;

    var seen = new Map();
    function clone(v) {
      if (v === null || v === undefined) return v;
      var tv = typeof v;
      if (tv === 'number' || tv === 'string' || tv === 'boolean' || tv === 'bigint') return v;
      if (tv === 'symbol' || tv === 'function')
        throw new DOMException('structuredClone: not cloneable', 'DataCloneError');

      if (seen.has(v)) return seen.get(v);

      if (v instanceof Date) {
        var d = new Date(v.getTime());
        seen.set(v, d);
        return d;
      }
      if (v instanceof RegExp) {
        var r = new RegExp(v.source, v.flags);
        seen.set(v, r);
        return r;
      }
      if (v instanceof ArrayBuffer) {
        var ab = v.slice(0);
        seen.set(v, ab);
        return ab;
      }
      if (ArrayBuffer.isView(v)) {
        var buf = v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength);
        var ctor = v.constructor;
        var ta = new ctor(buf);
        seen.set(v, ta);
        return ta;
      }
      if (v instanceof Map) {
        var m = new Map();
        seen.set(v, m);
        v.forEach(function(val, key) { m.set(clone(key), clone(val)); });
        return m;
      }
      if (v instanceof Set) {
        var s = new Set();
        seen.set(v, s);
        v.forEach(function(val) { s.add(clone(val)); });
        return s;
      }
      if (v instanceof Error) {
        var e = new (v.constructor || Error)(v.message);
        seen.set(v, e);
        if (v.name !== undefined) e.name = v.name;
        if (v.stack !== undefined) e.stack = v.stack;
        if (v.cause !== undefined) e.cause = clone(v.cause);
        return e;
      }
      if (Array.isArray(v)) {
        var a = [];
        seen.set(v, a);
        for (var i = 0; i < v.length; i++) a[i] = clone(v[i]);
        return a;
      }

      var o = {};
      seen.set(v, o);
      var keys = Object.keys(v);
      for (var k = 0; k < keys.length; k++) {
        o[keys[k]] = clone(v[keys[k]]);
      }
      return o;
    }
    return clone(value);
  };
})();`;
}
