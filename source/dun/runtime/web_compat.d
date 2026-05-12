module dun.runtime.web_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installWebCompat(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installWebCompat");
    auto global = engine.getGlobal();

    // structuredClone (simplified: JSON round-trip)
    engine.setProperty(global, "structuredClone",
        engine.newFunction(&jsStructuredClone, "structuredClone", 1));

    // Pure-JS atob/btoa/TextEncoder/TextDecoder — avoids FFI overhead for JIT engines
    auto webRes = engine.eval(webCompatSource(), "<web-compat>");
    if (!webRes.isError)
        engine.freeValue(webRes.value);

    engine.freeValue(global);
}

private string webCompatSource() pure nothrow @safe
{
    enum src =
    // Base64 lookup tables (generated once, captured by closure)
    "(function(){"
    ~ "var B64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';"
    ~ "var B64R=new Uint8Array(128);"
    ~ "for(var i=0;i<64;i++)B64R[B64.charCodeAt(i)]=i;"

    // btoa: binary string → base64
    ~ "globalThis.btoa=function btoa(s){"
    ~ "s=String(s);"
    ~ "var len=s.length,r='',i=0;"
    ~ "while(i<len){"
    ~ "var a=s.charCodeAt(i++),b=i<len?s.charCodeAt(i++):256,c=i<len?s.charCodeAt(i++):256;"
    ~ "var n=(a<<16)|(b<256?b<<8:0)|(c<256?c:0);"
    ~ "r+=B64[(n>>18)&63]+B64[(n>>12)&63]+(b<256?B64[(n>>6)&63]:'=')+(c<256?B64[n&63]:'=');"
    ~ "}"
    ~ "return r;};"

    // atob: base64 → binary string (no regex, manual padding strip)
    ~ "globalThis.atob=function atob(s){"
    ~ "s=String(s);"
    ~ "var len=s.length;"
    ~ "while(len>0&&s.charCodeAt(len-1)===61)len--;"
    ~ "var r='',i=0;"
    ~ "while(i<len){"
    ~ "var a=B64R[s.charCodeAt(i++)],b=i<len?B64R[s.charCodeAt(i++)]:0,"
    ~ "c=i<len?B64R[s.charCodeAt(i++)]:64,d=i<len?B64R[s.charCodeAt(i++)]:64;"
    ~ "r+=String.fromCharCode((a<<2)|(b>>4));"
    ~ "if(c<64)r+=String.fromCharCode(((b&15)<<4)|(c>>2));"
    ~ "if(d<64)r+=String.fromCharCode(((c&3)<<6)|d);"
    ~ "}"
    ~ "return r;};"

    // TextEncoder — pure-JS UTF-8 encoding, no FFI crossing
    ~ "globalThis.TextEncoder=function TextEncoder(){"
    ~ "this.encoding='utf-8';"
    ~ "this.encode=function(s){"
    ~ "s=String(s);"
    ~ "var len=s.length,buf=new Uint8Array(len*3),pos=0,i=0;"
    ~ "while(i<len){"
    ~ "var c=s.charCodeAt(i++);"
    ~ "if(c<128){buf[pos++]=c;}"
    ~ "else if(c<2048){buf[pos++]=192|(c>>6);buf[pos++]=128|(c&63);}"
    ~ "else if(c>=55296&&c<56320&&i<len){"
    ~ "var c2=s.charCodeAt(i);"
    ~ "if(c2>=56320&&c2<57344){i++;var cp=((c-55296)<<10)+(c2-56320)+65536;"
    ~ "buf[pos++]=240|(cp>>18);buf[pos++]=128|((cp>>12)&63);buf[pos++]=128|((cp>>6)&63);buf[pos++]=128|(cp&63);}"
    ~ "else{buf[pos++]=239;buf[pos++]=191;buf[pos++]=189;}}"
    ~ "else{buf[pos++]=224|(c>>12);buf[pos++]=128|((c>>6)&63);buf[pos++]=128|(c&63);}"
    ~ "}"
    ~ "return buf.subarray(0,pos);};"
    ~ "this.encodeInto=function(s,u8){var e=this.encode(s);var w=Math.min(e.length,u8.length);u8.set(e.subarray(0,w));return{read:s.length,written:w};};"
    ~ "};"

    // TextDecoder — pure-JS UTF-8 decoding
    ~ "globalThis.TextDecoder=function TextDecoder(){"
    ~ "this.encoding='utf-8';"
    ~ "this.decode=function(b){"
    ~ "if(typeof b==='string')return b;"
    ~ "if(!b||!b.length)return '';"
    ~ "var r='',i=0,len=b.length;"
    ~ "while(i<len){"
    ~ "var c=b[i++];"
    ~ "if(c<128){r+=String.fromCharCode(c);}"
    ~ "else if(c<224){r+=String.fromCharCode(((c&31)<<6)|(b[i++]&63));}"
    ~ "else if(c<240){r+=String.fromCharCode(((c&15)<<12)|((b[i++]&63)<<6)|(b[i++]&63));}"
    ~ "else{var cp=((c&7)<<18)|((b[i++]&63)<<12)|((b[i++]&63)<<6)|(b[i++]&63);cp-=65536;r+=String.fromCharCode(55296+(cp>>10),56320+(cp&1023));}"
    ~ "}"
    ~ "return r;};"
    ~ "};"
    ~ "})();";
    static assert(src.length > 0, "webCompatSource must not be empty");
    return src;
}

private:

JSHandle jsStructuredClone(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in structuredClone");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    assert(engine !is null, "Null engine in structuredClone");

    if (args.length < 1)
        return engine.newUndefined();

    return deepClone(engine, args[0]);
}

JSHandle deepClone(IJSEngine engine, JSHandle val) @trusted
{
    assert(engine !is null, "Null engine in deepClone");
    if (engine.isNull(val) || engine.isUndefined(val))
        return val;
    if (engine.isString(val))
        return engine.newString(engine.extractString(val));
    if (engine.isNumber(val))
        return engine.newFloat(engine.extractFloat(val));
    if (engine.isBool(val))
        return engine.newBool(engine.extractBool(val));

    // For objects/arrays, use JSON round-trip via engine
    auto global = engine.getGlobal();
    auto jsonObj = engine.getProperty(global, "JSON");
    auto stringify = engine.getProperty(jsonObj, "stringify");
    auto parse = engine.getProperty(jsonObj, "parse");

    auto jsonStr = engine.callFunction(stringify, jsonObj, [val]);
    if (engine.isException(jsonStr))
    {
        engine.freeValue(parse);
        engine.freeValue(stringify);
        engine.freeValue(jsonObj);
        engine.freeValue(global);
        return engine.throwTypeError("structuredClone: not serializable");
    }

    auto result = engine.callFunction(parse, jsonObj, [jsonStr]);
    engine.freeValue(jsonStr);
    engine.freeValue(parse);
    engine.freeValue(stringify);
    engine.freeValue(jsonObj);
    engine.freeValue(global);

    if (engine.isException(result))
        return engine.throwTypeError("structuredClone: not serializable");

    return result;
}

