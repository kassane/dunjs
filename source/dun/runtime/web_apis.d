module dun.runtime.web_apis;


/++
 + `@trusted policy`: web API polyfill installer (101 globals
 + per CLAUDE.md table). Every `@trusted` is one of:
 +   1. `engine.eval` of large polyfill sources at install time
 +      (cached).
 +   2. Lazy-load getter shim for `installLazyExtras` — first
 +      access compiles + evaluates the lazy chunk.
 +   3. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +/
import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;

void installWebAPIs(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installWebAPIs");

    auto res = engine.eval(webAPIsSource(), "<web-apis>");
    if (res.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("[web-apis] eval error: ", engine.getException());
            stderr.flush();
        }
        catch (Exception) {}
    }
    else
        engine.freeValue(res.value);

    // Extras land via lazy getters — `Object.defineProperty` on
    // globalThis with a getter that compiles + evaluates the chunk on
    // first access. Avoids the JSC heap-pressure spike at install
    // time that triggered the concurrent-GC vs D-event-loop deadlock
    // on the eager-allocation path. The visible side-effect is
    // identical: `typeof X === 'function'` still resolves correctly.
    installLazyExtras(engine);

    bindNativeCryptoOnGlobal(engine);
}

private void installLazyExtras(IJSEngine engine) @trusted
{
    import dun.platform.arena : Appender;
    Appender!string sb;
    sb.put("(function(){");
    foreach (chunk; extrasSources())
    {
        // For each chunk, expose every defined global as a getter
        // that runs the chunk on first read. The chunk itself uses
        // `if (typeof globalThis.X === 'undefined')` guards, so it's
        // a no-op on subsequent calls.
        sb.put("var _ran_");
        sb.put(sanitizeTag(chunk.tag));
        sb.put("=false;");
    }
    sb.put("var _lazy=function(tag,names,src){");
    sb.put("var fire=function(){");
    sb.put("if(globalThis['__ran_'+tag])return;");
    sb.put("globalThis['__ran_'+tag]=true;");
    /* Delete every accessor first so the chunk's `if(typeof X==='undefined')`
       checks see an undefined data property (no getter to re-invoke). */
    sb.put("for(var i=0;i<names.length;i++)try{delete globalThis[names[i]];}catch(e){}");
    sb.put("try{(new Function(src))();}catch(e){console.log('lazy chunk '+tag+' err:'+e.message);}");
    sb.put("};");
    sb.put("names.forEach(function(n){");
    sb.put("try{Object.defineProperty(globalThis,n,{configurable:true,enumerable:true,");
    sb.put("get:function(){fire();return globalThis[n];},");
    sb.put("set:function(v){try{delete globalThis[n];}catch(e){}globalThis[n]=v;}});");
    sb.put("}catch(e){console.log('lazy defineProperty '+n+' err:'+e.message);}");
    sb.put("});};");
    foreach (chunk; extrasSources())
    {
        sb.put("_lazy(\"");
        sb.put(sanitizeTag(chunk.tag));
        sb.put("\",[");
        bool first = true;
        foreach (n; chunkGlobalNames(chunk.tag))
        {
            if (!first) sb.put(",");
            sb.put("\"");
            sb.put(n);
            sb.put("\"");
            first = false;
        }
        sb.put("],");
        sb.put(escapeJsLit(chunk.src));
        sb.put(");");
    }
    sb.put("})()");
    auto src = sb.data;
    auto r = engine.eval(src, "<web-extras-lazy>");
    if (r.isError)
    {
        try { import std.stdio : stderr; stderr.writeln("[web-extras-lazy] ", engine.getException()); }
        catch (Exception) {}
    }
    engine.freeValue(r.value);
}

private alias sanitizeTag = sanitizeTagSafe;

// Double-quoted JS literal — wraps the canonical helper with the
// outer `"..."` quotes.
private string escapeJsLit(string s) @safe
{
    import dun.builtins.helpers : escapeJsString;
    return "\"" ~ escapeJsString(s, '"') ~ "\"";
}

private string sanitizeTagSafe(string tag) pure @safe
{
    string out_;
    foreach (c; tag)
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            out_ ~= c;
    return out_;
}

private string[] chunkGlobalNames(string tag) pure nothrow @safe
{
    switch (tag)
    {
        case "<web-observers>":
            return ["IntersectionObserver", "MutationObserver", "ResizeObserver",
                    "IntersectionObserverEntry", "ResizeObserverEntry", "MutationRecord"];
        case "<web-transport>":
            return ["WebTransport", "WebTransportError",
                    "WebTransportBidirectionalStream", "WebTransportDatagramDuplexStream"];
        case "<web-rtc>":
            return ["RTCPeerConnection"];
        case "<indexeddb>":
            return ["indexedDB", "IDBDatabase", "IDBTransaction", "IDBObjectStore",
                    "IDBIndex", "IDBCursor", "IDBCursorWithValue", "IDBRequest",
                    "IDBOpenDBRequest", "IDBKeyRange", "IDBVersionChangeEvent", "IDBFactory"];
        case "<notification>":
            return ["Notification"];
        case "<cookie-store>":
            return ["CookieStore", "cookieStore", "CookieChangeEvent"];
        case "<file-reader-sync>":
            return ["FileReaderSync"];
        case "<image-bitmap>":
            return ["ImageBitmap", "createImageBitmap"];
        default:
            return [];
    }
}

private struct ExtrasChunk { string src; string tag; }

private ExtrasChunk[] extrasSources() pure nothrow @safe
{
    return [
        ExtrasChunk(observersSource(), "<web-observers>"),
        ExtrasChunk(webTransportSource(), "<web-transport>"),
        ExtrasChunk(webRtcSource(), "<web-rtc>"),
        ExtrasChunk(indexedDBSource(), "<indexeddb>"),
        ExtrasChunk(notificationSource(), "<notification>"),
        ExtrasChunk(cookieStoreSource(), "<cookie-store>"),
        ExtrasChunk(fileReaderSyncSource(), "<file-reader-sync>"),
        ExtrasChunk(imageBitmapSource(), "<image-bitmap>"),
    ];
}

private string observersSource() pure nothrow @safe
{
    return `(function(){
var mk=function(name){
  var C=function(cb){this._cb=cb;};
  C.prototype.observe=function(){};
  C.prototype.unobserve=function(){};
  C.prototype.disconnect=function(){};
  C.prototype.takeRecords=function(){return [];};
  globalThis[name]=C;
};
if(typeof globalThis.IntersectionObserver==='undefined')mk('IntersectionObserver');
if(typeof globalThis.MutationObserver==='undefined')mk('MutationObserver');
if(typeof globalThis.ResizeObserver==='undefined')mk('ResizeObserver');
if(typeof globalThis.IntersectionObserverEntry==='undefined')
  globalThis.IntersectionObserverEntry=function IntersectionObserverEntry(){};
if(typeof globalThis.ResizeObserverEntry==='undefined')
  globalThis.ResizeObserverEntry=function ResizeObserverEntry(){};
if(typeof globalThis.MutationRecord==='undefined')
  globalThis.MutationRecord=function MutationRecord(){};
})()`;
}

private string webTransportSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.WebTransport==='undefined'){
  globalThis.WebTransport=function WebTransport(url){
    throw new Error('WebTransport: not yet implemented (use dun:http3 for HTTP/3)');
  };
}
if(typeof globalThis.WebTransportError==='undefined'){
  globalThis.WebTransportError=function WebTransportError(message,opts){
    Error.call(this,message);this.message=message||'';
    this.source=(opts&&opts.source)||'stream';this.streamErrorCode=(opts&&opts.streamErrorCode)||null;
  };
  WebTransportError.prototype=Object.create(Error.prototype);
  WebTransportError.prototype.constructor=WebTransportError;
  WebTransportError.prototype.name='WebTransportError';
}
if(typeof globalThis.WebTransportBidirectionalStream==='undefined')
  globalThis.WebTransportBidirectionalStream=function WebTransportBidirectionalStream(){};
if(typeof globalThis.WebTransportDatagramDuplexStream==='undefined')
  globalThis.WebTransportDatagramDuplexStream=function WebTransportDatagramDuplexStream(){};
})()`;
}

private string webRtcSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.RTCPeerConnection==='undefined'){
  globalThis.RTCPeerConnection=function RTCPeerConnection(){
    throw new Error('RTCPeerConnection: not yet implemented');
  };
}
})()`;
}

private string indexedDBSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.indexedDB==='undefined'){
  globalThis.indexedDB={
    open:function(name,version){
      var req={readyState:'pending',result:null,error:null,onsuccess:null,onerror:null,onupgradeneeded:null,onblocked:null};
      Promise.resolve().then(function(){
        req.readyState='done';
        req.error={name:'NotSupportedError',message:'IndexedDB not supported in DunJS'};
        if(req.onerror)req.onerror({target:req,type:'error'});
      });
      return req;
    },
    deleteDatabase:function(name){
      var req={readyState:'pending',result:null,error:null,onsuccess:null,onerror:null};
      Promise.resolve().then(function(){
        req.readyState='done';
        if(req.onsuccess)req.onsuccess({target:req,type:'success'});
      });
      return req;
    },
    databases:function(){return Promise.resolve([]);},
    cmp:function(a,b){return a<b?-1:(a>b?1:0);}
  };
  ['IDBDatabase','IDBTransaction','IDBObjectStore','IDBIndex','IDBCursor','IDBCursorWithValue','IDBRequest','IDBOpenDBRequest','IDBKeyRange','IDBVersionChangeEvent','IDBFactory'].forEach(function(n){
    if(typeof globalThis[n]==='undefined')globalThis[n]=function(){};
  });
}
})()`;
}

private string notificationSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.Notification==='undefined'){
  globalThis.Notification=function Notification(title,opts){
    this.title=title;this.body=(opts&&opts.body)||'';this.icon=(opts&&opts.icon)||'';
    this.onclick=null;this.onclose=null;this.onerror=null;this.onshow=null;
  };
  Notification.permission='denied';
  Notification.requestPermission=function(cb){
    var p=Promise.resolve('denied');
    if(typeof cb==='function')p.then(cb);
    return p;
  };
  Notification.maxActions=2;
  Notification.prototype.close=function(){};
}
})()`;
}

private string cookieStoreSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.CookieStore==='undefined'){
  globalThis.CookieStore=function CookieStore(){
    EventTarget.call(this);
    this._d=new Map();
  };
  CookieStore.prototype=Object.create(EventTarget.prototype);
  CookieStore.prototype.constructor=CookieStore;
  CookieStore.prototype.get=async function(name){
    var key=typeof name==='string'?name:(name&&name.name);
    var v=this._d.get(key);return v?{name:key,value:v}:null;
  };
  CookieStore.prototype.getAll=async function(){
    var out=[];for(var [k,v] of this._d)out.push({name:k,value:v});return out;
  };
  CookieStore.prototype.set=async function(arg){
    var name=typeof arg==='string'?arg:arg.name;
    var value=typeof arg==='string'?arguments[1]:arg.value;
    this._d.set(name,value);
    this.dispatchEvent({type:'change',changed:[{name:name,value:value}],deleted:[]});
  };
  CookieStore.prototype.delete=async function(arg){
    var name=typeof arg==='string'?arg:arg.name;
    this._d.delete(name);
    this.dispatchEvent({type:'change',changed:[],deleted:[{name:name}]});
  };
  globalThis.cookieStore=new CookieStore();
  globalThis.CookieChangeEvent=function CookieChangeEvent(type,init){
    Event.call(this,type,init);init=init||{};
    this.changed=init.changed||[];this.deleted=init.deleted||[];
  };
  CookieChangeEvent.prototype=Object.create(Event.prototype);
  CookieChangeEvent.prototype.constructor=CookieChangeEvent;
}
})()`;
}

private string fileReaderSyncSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.FileReaderSync==='undefined'){
  globalThis.FileReaderSync=function FileReaderSync(){};
  var ts=['readAsText','readAsArrayBuffer','readAsDataURL','readAsBinaryString'];
  ts.forEach(function(m){
    FileReaderSync.prototype[m]=function(){
      throw new Error('FileReaderSync.'+m+': use async FileReader instead');
    };
  });
}
})()`;
}

private string imageBitmapSource() pure nothrow @safe
{
    return `(function(){
if(typeof globalThis.ImageBitmap==='undefined'){
  globalThis.ImageBitmap=function ImageBitmap(){
    this.width=0;this.height=0;this._closed=false;
  };
  ImageBitmap.prototype.close=function(){this._closed=true;};
}
if(typeof globalThis.createImageBitmap==='undefined'){
  globalThis.createImageBitmap=function(src,opts){
    var b=new ImageBitmap();
    if(src&&src.width!=null){b.width=src.width;b.height=src.height;}
    else if(src&&src.byteLength!=null){b.width=src.byteLength;b.height=1;}
    return Promise.resolve(b);
  };
}
})()`;
}

private void bindNativeCryptoOnGlobal(IJSEngine engine) @trusted
{
    import dun.builtins.crypto : jsCryptoRandomUUID, jsCryptoRandomBytes,
                                  installSubtleOnGlobalCrypto;
    auto global = engine.getGlobal();
    auto cryptoObj = engine.getProperty(global, "crypto");
    if (!engine.isUndefined(cryptoObj) && !engine.isNull(cryptoObj))
    {
        engine.setProperty(cryptoObj, "randomUUID",
            engine.newFunction(&jsCryptoRandomUUID, "randomUUID", 0));
        engine.setProperty(cryptoObj, "getRandomValues",
            engine.newFunction(&jsNativeGetRandomValues, "getRandomValues", 1));
    }
    engine.freeValue(cryptoObj);
    engine.freeValue(global);

    // Install native crypto.subtle on the global crypto object
    installSubtleOnGlobalCrypto(engine);
}

private JSHandle jsNativeGetRandomValues(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in getRandomValues");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("Expected typed array");

    auto bytes = engine.getTypedArrayBytes(args[0]);
    if (bytes is null)
        return engine.throwTypeError("Expected typed array");

    import dun.builtins.crypto : fillRandomBytesPublic;
    fillRandomBytesPublic(bytes);
    return engine.dupValue(args[0]);
}

private string webAPIsSource() pure nothrow @safe
{
    enum src =
    "(function(){"

    // ═══════════════════════════════════
    // performance (High Resolution Time)
    // ═══════════════════════════════════
    ~ "var _perfOrigin=Date.now();"
    ~ "if(!globalThis.performance)globalThis.performance={};"
    ~ "try{Object.defineProperty(performance,'timeOrigin',{value:_perfOrigin,writable:true,configurable:true});}catch(e){performance.timeOrigin=_perfOrigin;}"
    ~ "performance.now=performance.now||function(){return Date.now()-_perfOrigin;};"
    ~ "performance.mark=function(){};"
    ~ "performance.measure=function(){};"
    ~ "performance.getEntriesByName=function(){return[];};"
    ~ "performance.getEntriesByType=function(){return[];};"
    ~ "performance.clearMarks=function(){};"
    ~ "performance.clearMeasures=function(){};"

    // ═══════════════════════════════════
    // Event / EventTarget (Web API base)
    // ═══════════════════════════════════
    ~ "globalThis.Event=function Event(type,opts){"
    ~ "this.type=type;this.bubbles=!!(opts&&opts.bubbles);this.cancelable=!!(opts&&opts.cancelable);"
    ~ "this.defaultPrevented=false;this.target=null;this.currentTarget=null;"
    ~ "this.timeStamp=Date.now();this._stop=false;this._imm=false;"
    ~ "};"
    ~ "Event.prototype.preventDefault=function(){if(this.cancelable)this.defaultPrevented=true;};"
    ~ "Event.prototype.stopPropagation=function(){this._stop=true;};"
    ~ "Event.prototype.stopImmediatePropagation=function(){this._stop=true;this._imm=true;};"
    ~ "Event.prototype.composedPath=function(){return this.target?[this.target]:[];};"

    ~ "globalThis.CustomEvent=function CustomEvent(type,opts){"
    ~ "Event.call(this,type,opts);this.detail=opts&&opts.detail!==undefined?opts.detail:null;"
    ~ "};"
    ~ "CustomEvent.prototype=Object.create(Event.prototype);"
    ~ "CustomEvent.prototype.constructor=CustomEvent;"

    ~ "globalThis.EventTarget=function EventTarget(){this._listeners={};};"
    ~ "EventTarget.prototype.addEventListener=function(type,cb,opts){"
    ~ "if(typeof cb!=='function')return;"
    ~ "if(!this._listeners[type])this._listeners[type]=[];"
    ~ "var once=opts&&(opts===true?false:!!opts.once);"
    ~ "this._listeners[type].push({fn:cb,once:once});"
    ~ "};"
    ~ "EventTarget.prototype.removeEventListener=function(type,cb){"
    ~ "var arr=this._listeners[type];if(!arr)return;"
    ~ "this._listeners[type]=arr.filter(function(l){return l.fn!==cb;});"
    ~ "};"
    ~ "EventTarget.prototype.dispatchEvent=function(evt){"
    ~ "evt.target=this;evt.currentTarget=this;"
    ~ "var arr=this._listeners[evt.type];if(!arr)return true;"
    ~ "var rm=[];"
    ~ "for(var i=0;i<arr.length;i++){"
    ~ "arr[i].fn.call(this,evt);if(arr[i].once)rm.push(i);"
    ~ "if(evt._imm)break;}"
    ~ "for(var j=rm.length-1;j>=0;j--)arr.splice(rm[j],1);"
    ~ "return!evt.defaultPrevented;"
    ~ "};"

    // ═══════════════════════════════════
    // AbortController / AbortSignal
    // ═══════════════════════════════════
    ~ "function AbortSignal(){EventTarget.call(this);this.aborted=false;this.reason=undefined;}"
    ~ "AbortSignal.prototype=Object.create(EventTarget.prototype);"
    ~ "AbortSignal.prototype.constructor=AbortSignal;"
    ~ "AbortSignal.prototype.throwIfAborted=function(){if(this.aborted)throw this.reason;};"
    ~ "AbortSignal.abort=function(r){var s=new AbortSignal();s.aborted=true;s.reason=r||new DOMException('The operation was aborted','AbortError');return s;};"
    ~ "AbortSignal.timeout=function(ms){var s=new AbortSignal();setTimeout(function(){s.aborted=true;s.reason=new DOMException('The operation timed out','TimeoutError');s.dispatchEvent(new Event('abort'));},ms);return s;};"
    ~ "AbortSignal.any=function(signals){var s=new AbortSignal();function ch(sig){if(s.aborted)return;s.aborted=true;s.reason=sig.reason;s.dispatchEvent(new Event('abort'));};"
    ~ "for(var i=0;i<signals.length;i++){if(signals[i].aborted){ch(signals[i]);return s;}signals[i].addEventListener('abort',function(){ch(this);});}"
    ~ "return s;};"
    ~ "globalThis.AbortSignal=AbortSignal;"

    ~ "globalThis.AbortController=function AbortController(){this.signal=new AbortSignal();};"
    ~ "AbortController.prototype.abort=function(r){"
    ~ "if(this.signal.aborted)return;"
    ~ "this.signal.aborted=true;"
    ~ "this.signal.reason=r||new DOMException('The operation was aborted','AbortError');"
    ~ "this.signal.dispatchEvent(new Event('abort'));"
    ~ "};"

    // ═══════════════════════════════════
    // DOMException
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.DOMException==='undefined'){"
    ~ "globalThis.DOMException=function DOMException(msg,name){"
    ~ "Error.call(this,msg);this.message=msg||'';this.name=name||'Error';this.code=0;"
    ~ "};"
    ~ "DOMException.prototype=Object.create(Error.prototype);"
    ~ "DOMException.prototype.constructor=DOMException;"
    ~ "}"

    // ═══════════════════════════════════
    // Promise.withResolvers (ES2024)
    // ═══════════════════════════════════
    ~ "if(!Promise.withResolvers){"
    ~ "Promise.withResolvers=function(){var r,j;var p=new Promise(function(a,b){r=a;j=b;});return{promise:p,resolve:r,reject:j};};"
    ~ "}"

    // ═══════════════════════════════════
    // setImmediate / clearImmediate
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.setImmediate==='undefined'){"
    ~ "globalThis.setImmediate=function(fn){var a=[].slice.call(arguments,1);return setTimeout(function(){fn.apply(null,a);},0);};"
    ~ "globalThis.clearImmediate=function(id){clearTimeout(id);};"
    ~ "}"

    // ═══════════════════════════════════
    // navigator
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.navigator==='undefined'){"
    ~ "globalThis.navigator={userAgent:'DunJS/0.2.0',platform:typeof process!=='undefined'?process.platform:'unknown',"
    ~ "language:'en-US',languages:['en-US','en'],onLine:true,"
    ~ "hardwareConcurrency:typeof require==='function'?(function(){try{return require('os').cpus().length}catch(e){return 1}}()):1};"
    ~ "}"

    // ═══════════════════════════════════
    // Blob
    // ═══════════════════════════════════
    ~ "globalThis.Blob=function Blob(parts,opts){"
    ~ "this._parts=parts||[];this.type=(opts&&opts.type)||'';"
    ~ "var sz=0;for(var i=0;i<this._parts.length;i++){"
    ~ "var p=this._parts[i];"
    ~ "if(typeof p==='string')sz+=new TextEncoder().encode(p).length;"
    ~ "else if(p instanceof ArrayBuffer)sz+=p.byteLength;"
    ~ "else if(p instanceof Uint8Array||p instanceof Int8Array)sz+=p.byteLength;"
    ~ "else if(p instanceof Blob)sz+=p.size;"
    ~ "else sz+=String(p).length;"
    ~ "}"
    ~ "this.size=sz;"
    ~ "};"
    ~ "Blob.prototype.text=function(){var enc=new TextEncoder(),dec=new TextDecoder(),chunks=[];"
    ~ "for(var i=0;i<this._parts.length;i++){var p=this._parts[i];"
    ~ "if(typeof p==='string')chunks.push(p);"
    ~ "else if(p instanceof Uint8Array)chunks.push(dec.decode(p));"
    ~ "else if(p instanceof ArrayBuffer)chunks.push(dec.decode(new Uint8Array(p)));"
    ~ "else if(p instanceof Blob)chunks.push(p._toText());"
    ~ "else chunks.push(String(p));}"
    ~ "return Promise.resolve(chunks.join(''));};"
    ~ "Blob.prototype._toText=function(){var dec=new TextDecoder(),chunks=[];"
    ~ "for(var i=0;i<this._parts.length;i++){var p=this._parts[i];"
    ~ "if(typeof p==='string')chunks.push(p);"
    ~ "else if(p instanceof Uint8Array)chunks.push(dec.decode(p));"
    ~ "else chunks.push(String(p));}"
    ~ "return chunks.join('');};"
    ~ "Blob.prototype.arrayBuffer=function(){var enc=new TextEncoder(),total=this.size,buf=new Uint8Array(total),off=0;"
    ~ "for(var i=0;i<this._parts.length;i++){var p=this._parts[i];"
    ~ "if(typeof p==='string'){var b=enc.encode(p);buf.set(b,off);off+=b.length;}"
    ~ "else if(p instanceof Uint8Array){buf.set(p,off);off+=p.length;}"
    ~ "else if(p instanceof ArrayBuffer){buf.set(new Uint8Array(p),off);off+=p.byteLength;}"
    ~ "}"
    ~ "return Promise.resolve(buf.buffer);};"
    ~ "Blob.prototype.slice=function(start,end,type){"
    ~ "var buf=[];this.arrayBuffer().then(function(ab){buf.push(new Uint8Array(ab).slice(start||0,end));});"
    ~ "return new Blob(buf,{type:type||this.type});};"
    ~ "Blob.prototype.stream=function(){return new ReadableStream({start:function(c){this.arrayBuffer().then(function(b){c.enqueue(new Uint8Array(b));c.close();});}.bind(this)});};"

    // ═══════════════════════════════════
    // File (extends Blob)
    // ═══════════════════════════════════
    ~ "globalThis.File=function File(parts,name,opts){"
    ~ "Blob.call(this,parts,opts);this.name=name;this.lastModified=(opts&&opts.lastModified)||Date.now();"
    ~ "};"
    ~ "File.prototype=Object.create(Blob.prototype);"
    ~ "File.prototype.constructor=File;"

    // ═══════════════════════════════════
    // FormData
    // ═══════════════════════════════════
    ~ "globalThis.FormData=function FormData(){this._data=[];};"
    ~ "FormData.prototype.append=function(k,v,f){this._data.push({name:k,value:v,filename:f});};"
    ~ "FormData.prototype.delete=function(k){this._data=this._data.filter(function(e){return e.name!==k;});};"
    ~ "FormData.prototype.get=function(k){for(var i=0;i<this._data.length;i++)if(this._data[i].name===k)return this._data[i].value;return null;};"
    ~ "FormData.prototype.getAll=function(k){return this._data.filter(function(e){return e.name===k;}).map(function(e){return e.value;});};"
    ~ "FormData.prototype.has=function(k){return this._data.some(function(e){return e.name===k;});};"
    ~ "FormData.prototype.set=function(k,v,f){this.delete(k);this.append(k,v,f);};"
    ~ "FormData.prototype.entries=function(){return this._data.map(function(e){return[e.name,e.value];})[Symbol.iterator]();};"
    ~ "FormData.prototype.keys=function(){return this._data.map(function(e){return e.name;})[Symbol.iterator]();};"
    ~ "FormData.prototype.values=function(){return this._data.map(function(e){return e.value;})[Symbol.iterator]();};"
    ~ "FormData.prototype[Symbol.iterator]=FormData.prototype.entries;"
    ~ "FormData.prototype.forEach=function(cb,t){for(var i=0;i<this._data.length;i++)cb.call(t,this._data[i].value,this._data[i].name,this);};"

    // ═══════════════════════════════════
    // Headers (for Request/Response)
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.Headers==='undefined'){"
    ~ "globalThis.Headers=function Headers(init){this._map={};"
    ~ "if(init){if(init instanceof Headers){var self=this;init.forEach(function(v,k){self.append(k,v);});}"
    ~ "else if(Array.isArray(init)){for(var i=0;i<init.length;i++)this.append(init[i][0],init[i][1]);}"
    ~ "else{for(var k in init)if(init.hasOwnProperty(k))this.append(k,init[k]);}"
    ~ "}};"
    ~ "Headers.prototype.append=function(k,v){k=k.toLowerCase();if(!this._map[k])this._map[k]=[];this._map[k].push(String(v));};"
    ~ "Headers.prototype.delete=function(k){delete this._map[k.toLowerCase()];};"
    ~ "Headers.prototype.get=function(k){var a=this._map[k.toLowerCase()];return a?a.join(', '):null;};"
    ~ "Headers.prototype.has=function(k){return k.toLowerCase() in this._map;};"
    ~ "Headers.prototype.set=function(k,v){this._map[k.toLowerCase()]=[String(v)];};"
    ~ "Headers.prototype.forEach=function(cb,t){for(var k in this._map)if(this._map.hasOwnProperty(k))for(var i=0;i<this._map[k].length;i++)cb.call(t,this._map[k][i],k,this);};"
    ~ "Headers.prototype.entries=function(){var arr=[];for(var k in this._map)if(this._map.hasOwnProperty(k))for(var i=0;i<this._map[k].length;i++)arr.push([k,this._map[k][i]]);return arr[Symbol.iterator]();};"
    ~ "Headers.prototype.keys=function(){var arr=Object.keys(this._map);return arr[Symbol.iterator]();};"
    ~ "Headers.prototype.values=function(){var arr=[];for(var k in this._map)if(this._map.hasOwnProperty(k))for(var i=0;i<this._map[k].length;i++)arr.push(this._map[k][i]);return arr[Symbol.iterator]();};"
    ~ "Headers.prototype[Symbol.iterator]=Headers.prototype.entries;"
    ~ "}"

    // ═══════════════════════════════════
    // Request / Response (Fetch API)
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.Request==='undefined'){"
    ~ "globalThis.Request=function Request(input,init){"
    ~ "init=init||{};"
    ~ "if(typeof input==='string'){this.url=input;}"
    ~ "else if(input instanceof Request){this.url=input.url;init.method=init.method||input.method;init.headers=init.headers||input.headers;init.body=init.body||input._body;}"
    ~ "else{this.url=String(input);}"
    ~ "this.method=(init.method||'GET').toUpperCase();"
    ~ "this.headers=new Headers(init.headers);"
    ~ "this._body=init.body||null;"
    ~ "this.mode=init.mode||'cors';"
    ~ "this.credentials=init.credentials||'same-origin';"
    ~ "this.redirect=init.redirect||'follow';"
    ~ "this.referrer=init.referrer||'about:client';"
    ~ "this.signal=init.signal||null;"
    ~ "this.bodyUsed=false;"
    ~ "};"
    ~ "Request.prototype.clone=function(){return new Request(this.url,{method:this.method,headers:this.headers,body:this._body,mode:this.mode,credentials:this.credentials,redirect:this.redirect,signal:this.signal});};"
    ~ "Request.prototype.text=function(){this.bodyUsed=true;return Promise.resolve(this._body?String(this._body):'');};"
    ~ "Request.prototype.json=function(){return this.text().then(JSON.parse);};"
    ~ "Request.prototype.arrayBuffer=function(){this.bodyUsed=true;if(this._body instanceof ArrayBuffer)return Promise.resolve(this._body);var enc=new TextEncoder();return Promise.resolve(enc.encode(String(this._body||'')).buffer);};"
    ~ "Request.prototype.blob=function(){return this.arrayBuffer().then(function(ab){return new Blob([ab]);});};"
    ~ "Request.prototype.formData=function(){return Promise.reject(new TypeError('formData not supported on Request'));};"
    ~ "}"

    ~ "if(typeof globalThis.Response==='undefined'){"
    ~ "globalThis.Response=function Response(body,init){"
    ~ "init=init||{};"
    ~ "this._body=body||null;"
    ~ "this.status=init.status!==undefined?init.status:200;"
    ~ "this.statusText=init.statusText||'';"
    ~ "this.ok=this.status>=200&&this.status<300;"
    ~ "this.headers=new Headers(init.headers);"
    ~ "this.type='default';"
    ~ "this.url=init.url||'';"
    ~ "this.redirected=false;"
    ~ "this.bodyUsed=false;"
    ~ "};"
    ~ "Response.prototype.clone=function(){return new Response(this._body,{status:this.status,statusText:this.statusText,headers:this.headers});};"
    /* If _body is a ReadableStream (e.g. from Bun.spawn's stdout or
       Request body), drain it to text. Typed-array bodies are
       UTF-8-decoded (real Fetch spec); only true primitive / object
       bodies fall to String(). */
    ~ "Response.prototype.text=function(){"
    ~   "this.bodyUsed=true;"
    ~   "var b=this._body;"
    ~   "if(b instanceof Uint8Array)return Promise.resolve(new TextDecoder().decode(b));"
    ~   "if(b instanceof ArrayBuffer)return Promise.resolve(new TextDecoder().decode(new Uint8Array(b)));"
    ~   "if(b&&b.buffer instanceof ArrayBuffer&&typeof b.byteLength==='number')return Promise.resolve(new TextDecoder().decode(new Uint8Array(b.buffer,b.byteOffset||0,b.byteLength)));"
    ~   "if(b&&typeof b.getReader==='function'){"
    ~     "var reader=b.getReader();var dec=new TextDecoder();var out='';"
    ~     "return new Promise(function(resolve,reject){"
    ~       "function pump(){reader.read().then(function(r){"
    ~         "if(r.done){out+=dec.decode();resolve(out);return;}"
    ~         "var v=r.value;"
    ~         "if(v instanceof Uint8Array||(v&&v.buffer instanceof ArrayBuffer)){"
    ~           "out+=dec.decode(v,{stream:true});"
    ~         "}else if(v instanceof ArrayBuffer){"
    ~           "out+=dec.decode(new Uint8Array(v),{stream:true});"
    ~         "}else{out+=String(v);}"
    ~         "pump();"
    ~       "}).catch(reject);}"
    ~       "pump();"
    ~     "});"
    ~   "}"
    ~   "return Promise.resolve(b?String(b):'');"
    ~ "};"
    ~ "Response.prototype.json=function(){return this.text().then(JSON.parse);};"
    /* Same idea: drain a ReadableStream to ArrayBuffer if present;
       otherwise return raw bytes for typed-array bodies (must come
       BEFORE the toString-encode fallback so `new Response(new
       Uint8Array([72,105,33]))` doesn't get stringified to "72,105,33"
       and then UTF-8-encoded to 9 bytes). */
    ~ "Response.prototype.arrayBuffer=function(){"
    ~   "this.bodyUsed=true;"
    ~   "var b=this._body;"
    ~   "if(b instanceof ArrayBuffer)return Promise.resolve(b);"
    ~   "if(b instanceof Uint8Array||(b&&b.buffer instanceof ArrayBuffer&&typeof b.byteLength==='number'))"
    ~     "return Promise.resolve(b.buffer.slice(b.byteOffset||0,(b.byteOffset||0)+b.byteLength));"
    ~   "if(b&&typeof b.getReader==='function'){"
    ~     "var reader=b.getReader();var chunks=[];var total=0;"
    ~     "return new Promise(function(resolve,reject){"
    ~       "function pump(){reader.read().then(function(r){"
    ~         "if(r.done){"
    ~           "var ab=new ArrayBuffer(total);var view=new Uint8Array(ab);var off=0;"
    ~           "for(var i=0;i<chunks.length;i++){view.set(chunks[i],off);off+=chunks[i].length;}"
    ~           "resolve(ab);return;}"
    ~         "var v=r.value;"
    ~         "var bytes=v instanceof Uint8Array?v:(v&&v.buffer instanceof ArrayBuffer?new Uint8Array(v.buffer,v.byteOffset,v.byteLength):new TextEncoder().encode(String(v)));"
    ~         "chunks.push(bytes);total+=bytes.length;pump();"
    ~       "}).catch(reject);}"
    ~       "pump();"
    ~     "});"
    ~   "}"
    ~   "var enc=new TextEncoder();return Promise.resolve(enc.encode(String(b||'')).buffer);"
    ~ "};"
    ~ "Response.prototype.blob=function(){return this.arrayBuffer().then(function(ab){return new Blob([ab]);});};"
    ~ "Response.prototype.formData=function(){return Promise.reject(new TypeError('formData not supported on Response'));};"
    ~ "Response.json=function(data,init){init=init||{};var h=new Headers(init.headers);h.set('content-type','application/json');return new Response(JSON.stringify(data),{status:init.status||200,statusText:init.statusText||'',headers:h});};"
    ~ "Response.redirect=function(url,status){return new Response(null,{status:status||302,headers:{Location:url}});};"
    ~ "Response.error=function(){var r=new Response(null,{status:0});r.type='error';return r;};"
    ~ "}"

    // ═══════════════════════════════════
    // MessageChannel / MessagePort. Per WHATWG, setting `onmessage`
    // implicitly starts the port (so consumers don't need an
    // explicit `.start()` call). Message delivery happens in a
    // microtask so postMessage doesn't synchronously dispatch.
    // ═══════════════════════════════════
    ~ "globalThis.MessagePort=function MessagePort(){EventTarget.call(this);this._other=null;this._started=false;this._queue=[];};"
    ~ "MessagePort.prototype=Object.create(EventTarget.prototype);"
    ~ "MessagePort.prototype.constructor=MessagePort;"
    ~ "MessagePort.prototype.postMessage=function(msg){"
    ~ "if(!this._other)return;"
    ~ "var other=this._other,evt={type:'message',data:JSON.parse(JSON.stringify(msg)),target:other,currentTarget:other};"
    ~ "if(other._started){if(typeof other.onmessage==='function')other.onmessage(evt);other.dispatchEvent(evt);}"
    ~ "else other._queue.push(evt);"
    ~ "};"
    ~ "MessagePort.prototype.start=function(){this._started=true;var q=this._queue;this._queue=[];for(var i=0;i<q.length;i++){if(typeof this.onmessage==='function')this.onmessage(q[i]);this.dispatchEvent(q[i]);}};"
    ~ "MessagePort.prototype.close=function(){this._other=null;};"
    /* Auto-start on onmessage setter -- WHATWG MessagePort spec
       says assigning to onmessage implicitly calls start(). */
    ~ "Object.defineProperty(MessagePort.prototype,'onmessage',{"
    ~ "  configurable:true,"
    ~ "  get:function(){return this._onmessage;},"
    ~ "  set:function(fn){"
    ~ "    this._onmessage=fn;"
    ~ "    if(typeof fn==='function'&&!this._started)this.start();"
    ~ "  }"
    ~ "});"

    ~ "globalThis.MessageChannel=function MessageChannel(){"
    ~ "this.port1=new MessagePort();this.port2=new MessagePort();"
    ~ "this.port1._other=this.port2;this.port2._other=this.port1;"
    ~ "};"

    // ═══════════════════════════════════
    // BroadcastChannel
    // ═══════════════════════════════════
    ~ "var _bcChannels={};"
    ~ "globalThis.BroadcastChannel=function BroadcastChannel(name){"
    ~ "EventTarget.call(this);this.name=name;this.onmessage=null;"
    ~ "if(!_bcChannels[name])_bcChannels[name]=[];"
    ~ "_bcChannels[name].push(this);"
    ~ "};"
    ~ "BroadcastChannel.prototype=Object.create(EventTarget.prototype);"
    ~ "BroadcastChannel.prototype.constructor=BroadcastChannel;"
    ~ "BroadcastChannel.prototype.postMessage=function(msg){"
    ~ "var chs=_bcChannels[this.name]||[],self=this;"
    ~ "for(var i=0;i<chs.length;i++){if(chs[i]!==self){"
    ~ "var evt={type:'message',data:JSON.parse(JSON.stringify(msg)),target:chs[i]};"
    ~ "if(typeof chs[i].onmessage==='function')chs[i].onmessage(evt);"
    ~ "chs[i].dispatchEvent(evt);"
    ~ "}}};"
    ~ "BroadcastChannel.prototype.close=function(){"
    ~ "var chs=_bcChannels[this.name]||[];var idx=chs.indexOf(this);if(idx>=0)chs.splice(idx,1);"
    ~ "};"

    // ═══════════════════════════════════
    // EventSource — WHATWG Server-Sent Events (HTML §9.2).
    // Spec: https://html.spec.whatwg.org/multipage/server-sent-events.html
    // Layers on top of fetch(): streams the body line-by-line and
    // dispatches `message` (or named) events per the SSE format.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.EventSource==='undefined'){"
    ~ "var EventSource=globalThis.EventSource=function EventSource(url,init){"
    ~ "EventTarget.call(this);"
    ~ "this.url=String(url);"
    ~ "this.withCredentials=!!(init&&init.withCredentials);"
    ~ "this.readyState=0;" /* CONNECTING */
    ~ "this.onopen=null;this.onmessage=null;this.onerror=null;"
    ~ "this._lastEventId='';this._reconnectMs=3000;this._aborted=false;"
    ~ "var self=this;"
    ~ "this._connect=function(){"
    ~ "if(self._aborted)return;"
    ~ "var headers={'Accept':'text/event-stream','Cache-Control':'no-cache'};"
    ~ "if(self._lastEventId)headers['Last-Event-ID']=self._lastEventId;"
    ~ "fetch(self.url,{headers:headers,credentials:self.withCredentials?'include':'same-origin'})"
    ~ ".then(async function(res){"
    ~ "if(self._aborted)return;"
    ~ "if(!res.ok||!res.body){self._fail();return;}"
    ~ "self.readyState=1;" /* OPEN */
    ~ "var openEv={type:'open'};"
    ~ "if(self.onopen)self.onopen(openEv);"
    ~ "self.dispatchEvent(openEv);"
    ~ "var reader=res.body.getReader();var dec=new TextDecoder();var buf='';var eventType='message',data='',eventId='';"
    ~ "while(true){"
    ~ "var r=await reader.read();if(r.done)break;"
    ~ "buf+=dec.decode(r.value,{stream:true});"
    ~ "var lines=buf.split(/\\r\\n|\\r|\\n/);buf=lines.pop()||'';"
    ~ "for(var i=0;i<lines.length;i++){"
    ~ "var ln=lines[i];"
    ~ "if(ln===''){" /* dispatch */
    ~ "if(data){"
    ~ "if(eventId)self._lastEventId=eventId;"
    ~ "var ev={type:eventType,data:data.replace(/\\n$/,''),lastEventId:self._lastEventId,origin:new URL(self.url).origin};"
    ~ "if(eventType==='message'&&self.onmessage)self.onmessage(ev);"
    ~ "self.dispatchEvent(ev);"
    ~ "}"
    ~ "eventType='message';data='';eventId='';continue;"
    ~ "}"
    ~ "if(ln.charAt(0)===':')continue;" /* comment */
    ~ "var colonIdx=ln.indexOf(':');var field,value;"
    ~ "if(colonIdx===-1){field=ln;value='';}"
    ~ "else{field=ln.slice(0,colonIdx);value=ln.slice(colonIdx+1).replace(/^ /,'');}"
    ~ "if(field==='event')eventType=value;"
    ~ "else if(field==='data')data+=value+'\\n';"
    ~ "else if(field==='id')eventId=value;"
    ~ "else if(field==='retry'){var rt=parseInt(value,10);if(!isNaN(rt))self._reconnectMs=rt;}"
    ~ "}"
    ~ "}"
    ~ "self._fail();"
    ~ "}).catch(function(){self._fail();});"
    ~ "};"
    ~ "this._fail=function(){"
    ~ "if(self._aborted)return;"
    ~ "self.readyState=0;"
    ~ "var ev={type:'error'};if(self.onerror)self.onerror(ev);self.dispatchEvent(ev);"
    ~ "setTimeout(function(){self._connect();},self._reconnectMs);"
    ~ "};"
    ~ "this.close=function(){self._aborted=true;self.readyState=2;};"
    ~ "this._connect();"
    ~ "};"
    ~ "EventSource.prototype=Object.create(EventTarget.prototype);"
    ~ "EventSource.prototype.constructor=EventSource;"
    ~ "EventSource.CONNECTING=0;EventSource.OPEN=1;EventSource.CLOSED=2;"
    ~ "}"

    // ═══════════════════════════════════
    // URLPattern — WHATWG URL Pattern API.
    // Spec: https://urlpattern.spec.whatwg.org/
    // Minimal impl: supports pattern strings like "/users/:id" and
    // structured init objects ({ pathname, hostname, search }).
    // Returns { groups, input } for matched components on .exec().
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.URLPattern==='undefined'){"
    ~ "globalThis.URLPattern=function URLPattern(init,baseURL){"
    ~ "if(typeof init==='string'){this.pathname=init;}"
    ~ "else if(init&&typeof init==='object'){"
    ~ "this.protocol=init.protocol||'*';this.username=init.username||'*';this.password=init.password||'*';"
    ~ "this.hostname=init.hostname||'*';this.port=init.port||'*';this.pathname=init.pathname||'*';"
    ~ "this.search=init.search||'*';this.hash=init.hash||'*';"
    ~ "}"
    ~ "var self=this;"
    ~ "this._compile=function(pat){"
    ~ "if(pat==='*')return{regex:/.*/,keys:[]};"
    ~ "var keys=[],re='';"
    ~ "for(var i=0;i<pat.length;i++){"
    ~ "var c=pat[i];"
    ~ "if(c===':'){"
    ~ "var end=i+1;while(end<pat.length&&/[A-Za-z0-9_]/.test(pat[end]))end++;"
    ~ "keys.push(pat.slice(i+1,end));re+='([^/]+)';i=end-1;"
    ~ "}"
    ~ "else if(c==='*')re+='(.*)';"
    ~ "else if('.+^${}()|[]\\\\'.indexOf(c)!==-1)re+='\\\\'+c;"
    ~ "else re+=c;"
    ~ "}"
    ~ "return{regex:new RegExp('^'+re+'$'),keys:keys};"
    ~ "};"
    ~ "var pathParts=this._compile(this.pathname||'*');"
    ~ "this._pathRegex=pathParts.regex;this._pathKeys=pathParts.keys;"
    ~ "this.exec=function(input){"
    ~ "var pathname=input;"
    ~ "if(typeof input==='string'&&input.indexOf('://')!==-1){"
    ~ "try{var u=new URL(input);pathname=u.pathname;}catch(e){return null;}"
    ~ "}"
    ~ "else if(input&&typeof input==='object'){pathname=input.pathname||'';}"
    ~ "var m=self._pathRegex.exec(pathname);"
    ~ "if(!m)return null;"
    ~ "var groups={};for(var i=0;i<self._pathKeys.length;i++)groups[self._pathKeys[i]]=m[i+1];"
    ~ "return{pathname:{input:pathname,groups:groups},input:input};"
    ~ "};"
    ~ "this.test=function(input){return self.exec(input)!==null;};"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // ReadableStream (simplified Web Streams)
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.ReadableStream==='undefined'){"
    ~ "globalThis.ReadableStream=function ReadableStream(source){"
    ~ "this._source=source||{};this._queue=[];this._closed=false;this._started=false;this._reader=null;this._pendingReads=[];"
    ~ "var self=this;"
    /* Enqueue: push chunk; if a pending read is waiting, resolve it. */
    ~ "this._controller={enqueue:function(chunk){"
    ~   "if(self._closed)return;"
    ~   "if(self._pendingReads.length>0){self._pendingReads.shift()({value:chunk,done:false});}"
    ~   "else{self._queue.push(chunk);}"
    ~ "},close:function(){"
    ~   "self._closed=true;"
    ~   "while(self._pendingReads.length>0)self._pendingReads.shift()({value:undefined,done:true});"
    ~ "},error:function(e){self._errored=e;self._closed=true;"
    ~   "while(self._pendingReads.length>0)self._pendingReads.shift()({value:undefined,done:true});"
    ~ "},desiredSize:1};"
    ~ "if(this._source.start){try{this._source.start(this._controller);}catch(e){this._errored=e;this._closed=true;}}"
    ~ "this._started=true;"
    ~ "};"
    ~ "ReadableStream.prototype.getReader=function(){"
    ~ "if(this._reader)throw new TypeError('ReadableStream already locked');"
    ~ "var stream=this;this._reader={_stream:stream,closed:new Promise(function(){}),read:function(){"
    ~ "if(stream._source.pull&&!stream._closed&&stream._queue.length===0){"
    ~ "return new Promise(function(res){stream._source.pull({enqueue:function(v){res({value:v,done:false});},close:function(){stream._closed=true;res({value:undefined,done:true});}});});"
    ~ "}"
    ~ "if(stream._queue.length>0)return Promise.resolve({value:stream._queue.shift(),done:false});"
    ~ "if(stream._closed)return Promise.resolve({value:undefined,done:true});"
    /* Source has no `pull`, stream not closed yet, queue empty: park
       a pending read promise. The next `controller.enqueue` or
       `controller.close` call resolves it. Required for push-based
       sources like Readable.toWeb where data arrives via events. */
    ~ "return new Promise(function(res){stream._pendingReads.push(res);});"
    ~ "},releaseLock:function(){stream._reader=null;},cancel:function(){stream._closed=true;if(stream._source.cancel)stream._source.cancel();return Promise.resolve();}};"
    ~ "return this._reader;};"
    ~ "ReadableStream.prototype.cancel=function(){this._closed=true;if(this._source.cancel)this._source.cancel();return Promise.resolve();};"
    ~ "ReadableStream.prototype[Symbol.asyncIterator]=function(){var reader=this.getReader();return{next:function(){return reader.read();},return:function(){reader.releaseLock();return Promise.resolve({value:undefined,done:true});}};};"
    ~ "ReadableStream.from=function(iter){return new ReadableStream({start:function(c){"
    ~ "if(iter[Symbol.asyncIterator]){var it=iter[Symbol.asyncIterator]();function pump(){it.next().then(function(r){if(r.done){c.close();}else{c.enqueue(r.value);pump();}});}pump();}"
    ~ "else if(iter[Symbol.iterator]){var it2=iter[Symbol.iterator](),r;while(!(r=it2.next()).done)c.enqueue(r.value);c.close();}"
    ~ "else{c.enqueue(iter);c.close();}"
    ~ "}});};"
    ~ "}"

    // WritableStream (simplified)
    ~ "if(typeof globalThis.WritableStream==='undefined'){"
    ~ "globalThis.WritableStream=function WritableStream(sink){"
    ~ "this._sink=sink||{};this._closed=false;this._writer=null;"
    ~ "if(this._sink.start)this._sink.start({});"
    ~ "};"
    ~ "WritableStream.prototype.getWriter=function(){"
    ~ "if(this._writer)throw new TypeError('WritableStream already locked');"
    ~ "var stream=this;this._writer={_stream:stream,"
    ~ "write:function(chunk){if(stream._sink.write)return Promise.resolve(stream._sink.write(chunk));return Promise.resolve();},"
    ~ "close:function(){stream._closed=true;if(stream._sink.close)stream._sink.close();stream._writer=null;return Promise.resolve();},"
    ~ "abort:function(r){stream._closed=true;if(stream._sink.abort)stream._sink.abort(r);stream._writer=null;return Promise.resolve();},"
    ~ "releaseLock:function(){stream._writer=null;},"
    ~ "closed:new Promise(function(){}),ready:Promise.resolve(),desiredSize:1};"
    ~ "return this._writer;};"
    ~ "WritableStream.prototype.close=function(){this._closed=true;if(this._sink.close)this._sink.close();return Promise.resolve();};"
    ~ "WritableStream.prototype.abort=function(r){this._closed=true;if(this._sink.abort)this._sink.abort(r);return Promise.resolve();};"
    ~ "}"

    // TransformStream (simplified)
    ~ "if(typeof globalThis.TransformStream==='undefined'){"
    ~ "globalThis.TransformStream=function TransformStream(transformer){"
    ~ "transformer=transformer||{};var readable_queue=[],readable_closed=false,writable_closed=false;"
    ~ "var tc={enqueue:function(chunk){readable_queue.push(chunk);},terminate:function(){readable_closed=true;},error:function(e){readable_closed=true;}};"
    ~ "this.readable=new ReadableStream({pull:function(controller){if(readable_queue.length>0)controller.enqueue(readable_queue.shift());"
    ~ "else if(readable_closed)controller.close();}});"
    ~ "var self=this;"
    ~ "this.writable=new WritableStream({"
    ~ "write:function(chunk){if(transformer.transform)transformer.transform(chunk,tc);else tc.enqueue(chunk);},"
    ~ "close:function(){if(transformer.flush)transformer.flush(tc);readable_closed=true;}"
    ~ "});"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // CompressionStream / DecompressionStream (Web Compression API)
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.CompressionStream==='undefined'){"
    ~ "globalThis.CompressionStream=function CompressionStream(format){"
    ~ "if(format!=='gzip'&&format!=='deflate'&&format!=='deflate-raw')"
    ~ "throw new TypeError(\"Unsupported compression format: \"+format);"
    ~ "this.format=format;"
    ~ "this.readable=new ReadableStream({});"
    ~ "this.writable=new WritableStream({});"
    ~ "};"
    ~ "}"

    ~ "if(typeof globalThis.DecompressionStream==='undefined'){"
    ~ "globalThis.DecompressionStream=function DecompressionStream(format){"
    ~ "if(format!=='gzip'&&format!=='deflate'&&format!=='deflate-raw')"
    ~ "throw new TypeError(\"Unsupported compression format: \"+format);"
    ~ "this.format=format;"
    ~ "this.readable=new ReadableStream({});"
    ~ "this.writable=new WritableStream({});"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // QueuingStrategy subclasses — required by ReadableStream byob
    // mode and TransformStream constructors. Both are 1-property
    // value classes per WHATWG Streams §7.{1,2}.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.ByteLengthQueuingStrategy==='undefined'){"
    ~ "globalThis.ByteLengthQueuingStrategy=function ByteLengthQueuingStrategy(init){"
    ~ "this.highWaterMark=init&&init.highWaterMark;"
    ~ "this.size=function(chunk){return chunk&&chunk.byteLength||0;};"
    ~ "};"
    ~ "}"
    ~ "if(typeof globalThis.CountQueuingStrategy==='undefined'){"
    ~ "globalThis.CountQueuingStrategy=function CountQueuingStrategy(init){"
    ~ "this.highWaterMark=init&&init.highWaterMark;"
    ~ "this.size=function(){return 1;};"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // TextEncoderStream / TextDecoderStream — transform streams
    // backed by the existing TextEncoder/Decoder.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.TextEncoderStream==='undefined'){"
    ~ "globalThis.TextEncoderStream=function TextEncoderStream(){"
    ~ "var enc=new TextEncoder();"
    ~ "var ts=new TransformStream({"
    ~ "transform:function(chunk,controller){controller.enqueue(enc.encode(chunk));}"
    ~ "});"
    ~ "this.encoding=enc.encoding;"
    ~ "this.readable=ts.readable;"
    ~ "this.writable=ts.writable;"
    ~ "};"
    ~ "}"
    ~ "if(typeof globalThis.TextDecoderStream==='undefined'){"
    ~ "globalThis.TextDecoderStream=function TextDecoderStream(label,options){"
    ~ "var dec=new TextDecoder(label,options);"
    ~ "var ts=new TransformStream({"
    ~ "transform:function(chunk,controller){var s=dec.decode(chunk,{stream:true});if(s)controller.enqueue(s);},"
    ~ "flush:function(controller){var s=dec.decode();if(s)controller.enqueue(s);}"
    ~ "});"
    ~ "this.encoding=dec.encoding;"
    ~ "this.fatal=dec.fatal;"
    ~ "this.ignoreBOM=dec.ignoreBOM;"
    ~ "this.readable=ts.readable;"
    ~ "this.writable=ts.writable;"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // crypto.getRandomValues()
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.crypto==='undefined')globalThis.crypto={};"

    // ═══════════════════════════════════
    // Event subclasses — MessageEvent, ErrorEvent, PromiseRejectionEvent,
    // CloseEvent. All extend Event with their named data fields.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.MessageEvent==='undefined'){"
    ~ "globalThis.MessageEvent=function MessageEvent(type,init){"
    ~ "Event.call(this,type,init);init=init||{};"
    ~ "this.data=init.data;this.origin=init.origin||'';this.lastEventId=init.lastEventId||'';"
    ~ "this.source=init.source||null;this.ports=init.ports||[];"
    ~ "};"
    ~ "MessageEvent.prototype=Object.create(Event.prototype);"
    ~ "MessageEvent.prototype.constructor=MessageEvent;"
    ~ "}"
    ~ "if(typeof globalThis.ErrorEvent==='undefined'){"
    ~ "globalThis.ErrorEvent=function ErrorEvent(type,init){"
    ~ "Event.call(this,type,init);init=init||{};"
    ~ "this.message=init.message||'';this.filename=init.filename||'';"
    ~ "this.lineno=init.lineno||0;this.colno=init.colno||0;this.error=init.error||null;"
    ~ "};"
    ~ "ErrorEvent.prototype=Object.create(Event.prototype);"
    ~ "ErrorEvent.prototype.constructor=ErrorEvent;"
    ~ "}"
    ~ "if(typeof globalThis.PromiseRejectionEvent==='undefined'){"
    ~ "globalThis.PromiseRejectionEvent=function PromiseRejectionEvent(type,init){"
    ~ "Event.call(this,type,init);init=init||{};"
    ~ "this.promise=init.promise;this.reason=init.reason;"
    ~ "};"
    ~ "PromiseRejectionEvent.prototype=Object.create(Event.prototype);"
    ~ "PromiseRejectionEvent.prototype.constructor=PromiseRejectionEvent;"
    ~ "}"
    ~ "if(typeof globalThis.CloseEvent==='undefined'){"
    ~ "globalThis.CloseEvent=function CloseEvent(type,init){"
    ~ "Event.call(this,type,init);init=init||{};"
    ~ "this.wasClean=!!init.wasClean;this.code=init.code||1005;this.reason=init.reason||'';"
    ~ "};"
    ~ "CloseEvent.prototype=Object.create(Event.prototype);"
    ~ "CloseEvent.prototype.constructor=CloseEvent;"
    ~ "}"

    // ═══════════════════════════════════
    // Web Storage — localStorage / sessionStorage / Storage class.
    // In-memory only (no disk persistence yet — Node/Bun behave the
    // same in non-DOM contexts).
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.Storage==='undefined'){"
    ~ "globalThis.Storage=function Storage(){this._d={};};"
    ~ "Storage.prototype.getItem=function(k){return this._d.hasOwnProperty(k)?this._d[k]:null;};"
    ~ "Storage.prototype.setItem=function(k,v){this._d[String(k)]=String(v);};"
    ~ "Storage.prototype.removeItem=function(k){delete this._d[k];};"
    ~ "Storage.prototype.clear=function(){this._d={};};"
    ~ "Storage.prototype.key=function(i){return Object.keys(this._d)[i]||null;};"
    ~ "Object.defineProperty(Storage.prototype,'length',{get:function(){return Object.keys(this._d).length;}});"
    ~ "globalThis.localStorage=new Storage();"
    ~ "globalThis.sessionStorage=new Storage();"
    ~ "}"

    // ═══════════════════════════════════
    // Cache API — caches / CacheStorage / Cache. In-memory only;
    // matches the Service Worker Cache Storage spec surface but
    // doesn't share entries across processes.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.CacheStorage==='undefined'){"
    ~ "globalThis.Cache=function Cache(){this._d=new Map();};"
    ~ "Cache.prototype.match=async function(req){"
    ~ "var key=typeof req==='string'?req:(req&&req.url)||String(req);"
    ~ "return this._d.get(key);"
    ~ "};"
    ~ "Cache.prototype.put=async function(req,res){"
    ~ "var key=typeof req==='string'?req:(req&&req.url)||String(req);"
    ~ "this._d.set(key,res);"
    ~ "};"
    ~ "Cache.prototype.add=async function(req){"
    ~ "var res=await fetch(req);await this.put(req,res);"
    ~ "};"
    ~ "Cache.prototype.addAll=async function(reqs){"
    ~ "for(var i=0;i<reqs.length;i++)await this.add(reqs[i]);"
    ~ "};"
    ~ "Cache.prototype.delete=async function(req){"
    ~ "var key=typeof req==='string'?req:(req&&req.url)||String(req);"
    ~ "return this._d.delete(key);"
    ~ "};"
    ~ "Cache.prototype.keys=async function(){return Array.from(this._d.keys()).map(function(k){return new Request(k);});};"
    ~ "Cache.prototype.matchAll=async function(){return Array.from(this._d.values());};"
    ~ "globalThis.CacheStorage=function CacheStorage(){this._d=new Map();};"
    ~ "CacheStorage.prototype.open=async function(name){"
    ~ "if(!this._d.has(name))this._d.set(name,new Cache());"
    ~ "return this._d.get(name);"
    ~ "};"
    ~ "CacheStorage.prototype.has=async function(name){return this._d.has(name);};"
    ~ "CacheStorage.prototype.delete=async function(name){return this._d.delete(name);};"
    ~ "CacheStorage.prototype.keys=async function(){return Array.from(this._d.keys());};"
    ~ "CacheStorage.prototype.match=async function(req){"
    ~ "for(var c of this._d.values()){var r=await c.match(req);if(r)return r;}"
    ~ "return undefined;"
    ~ "};"
    ~ "globalThis.caches=new CacheStorage();"
    ~ "}"

    // ═══════════════════════════════════
    // FileReader — sync + async paths over Blob/File. Minimal impl
    // sufficient for libraries that read uploads / fs results into
    // text / dataURL form.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.FileReader==='undefined'){"
    ~ "globalThis.FileReader=function FileReader(){"
    ~ "EventTarget.call(this);"
    ~ "this.readyState=0;this.result=null;this.error=null;"
    ~ "this.onload=null;this.onloadend=null;this.onloadstart=null;this.onerror=null;this.onabort=null;this.onprogress=null;"
    ~ "};"
    ~ "FileReader.prototype=Object.create(EventTarget.prototype);"
    ~ "FileReader.prototype.constructor=FileReader;"
    ~ "FileReader.EMPTY=0;FileReader.LOADING=1;FileReader.DONE=2;"
    ~ "FileReader.prototype._fire=function(name,ev){"
    ~ "var h=this['on'+name];if(typeof h==='function')h.call(this,ev||{type:name,target:this});"
    ~ "this.dispatchEvent(ev||{type:name,target:this});"
    ~ "};"
    ~ "FileReader.prototype._run=function(blob,mode){"
    ~ "var self=this;self.readyState=1;self._fire('loadstart');"
    ~ "Promise.resolve().then(async function(){"
    ~ "try{"
    ~ "if(mode==='text'){self.result=await blob.text();}"
    ~ "else if(mode==='arrayBuffer'){self.result=await blob.arrayBuffer();}"
    ~ "else if(mode==='dataURL'){"
    ~ "var buf=new Uint8Array(await blob.arrayBuffer());"
    ~ "var bin='';for(var i=0;i<buf.length;i++)bin+=String.fromCharCode(buf[i]);"
    ~ "self.result='data:'+(blob.type||'application/octet-stream')+';base64,'+btoa(bin);"
    ~ "}"
    ~ "else if(mode==='binaryString'){"
    ~ "var buf2=new Uint8Array(await blob.arrayBuffer());"
    ~ "var b='';for(var j=0;j<buf2.length;j++)b+=String.fromCharCode(buf2[j]);"
    ~ "self.result=b;"
    ~ "}"
    ~ "self.readyState=2;self._fire('load');self._fire('loadend');"
    ~ "}catch(e){self.error=e;self.readyState=2;self._fire('error');self._fire('loadend');}"
    ~ "});"
    ~ "};"
    ~ "FileReader.prototype.readAsText=function(blob){this._run(blob,'text');};"
    ~ "FileReader.prototype.readAsArrayBuffer=function(blob){this._run(blob,'arrayBuffer');};"
    ~ "FileReader.prototype.readAsDataURL=function(blob){this._run(blob,'dataURL');};"
    ~ "FileReader.prototype.readAsBinaryString=function(blob){this._run(blob,'binaryString');};"
    ~ "FileReader.prototype.abort=function(){if(this.readyState===1){this.readyState=2;this._fire('abort');this._fire('loadend');}};"
    ~ "}"

    // ═══════════════════════════════════
    // DOM geometry — DOMRect / DOMRectReadOnly / DOMPoint /
    // DOMPointReadOnly / DOMMatrix / DOMMatrixReadOnly / DOMQuad.
    // Plain value classes per the Geometry Interfaces spec.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.DOMPointReadOnly==='undefined'){"
    ~ "globalThis.DOMPointReadOnly=function DOMPointReadOnly(x,y,z,w){"
    ~ "this.x=+x||0;this.y=+y||0;this.z=+z||0;this.w=w==null?1:+w;"
    ~ "};"
    ~ "DOMPointReadOnly.fromPoint=function(p){p=p||{};return new DOMPointReadOnly(p.x,p.y,p.z,p.w);};"
    ~ "globalThis.DOMPoint=function DOMPoint(x,y,z,w){DOMPointReadOnly.call(this,x,y,z,w);};"
    ~ "DOMPoint.prototype=Object.create(DOMPointReadOnly.prototype);"
    ~ "DOMPoint.prototype.constructor=DOMPoint;"
    ~ "DOMPoint.fromPoint=DOMPointReadOnly.fromPoint;"
    ~ "}"
    ~ "if(typeof globalThis.DOMRectReadOnly==='undefined'){"
    ~ "globalThis.DOMRectReadOnly=function DOMRectReadOnly(x,y,w,h){"
    ~ "this.x=+x||0;this.y=+y||0;this.width=+w||0;this.height=+h||0;"
    ~ "};"
    ~ "Object.defineProperty(DOMRectReadOnly.prototype,'top',{get:function(){return this.y;}});"
    ~ "Object.defineProperty(DOMRectReadOnly.prototype,'left',{get:function(){return this.x;}});"
    ~ "Object.defineProperty(DOMRectReadOnly.prototype,'right',{get:function(){return this.x+this.width;}});"
    ~ "Object.defineProperty(DOMRectReadOnly.prototype,'bottom',{get:function(){return this.y+this.height;}});"
    ~ "DOMRectReadOnly.fromRect=function(r){r=r||{};return new DOMRectReadOnly(r.x,r.y,r.width,r.height);};"
    ~ "globalThis.DOMRect=function DOMRect(x,y,w,h){DOMRectReadOnly.call(this,x,y,w,h);};"
    ~ "DOMRect.prototype=Object.create(DOMRectReadOnly.prototype);"
    ~ "DOMRect.prototype.constructor=DOMRect;"
    ~ "DOMRect.fromRect=DOMRectReadOnly.fromRect;"
    ~ "}"
    ~ "if(typeof globalThis.DOMQuad==='undefined'){"
    ~ "globalThis.DOMQuad=function DOMQuad(p1,p2,p3,p4){"
    ~ "this.p1=DOMPoint.fromPoint(p1);this.p2=DOMPoint.fromPoint(p2);"
    ~ "this.p3=DOMPoint.fromPoint(p3);this.p4=DOMPoint.fromPoint(p4);"
    ~ "};"
    ~ "DOMQuad.prototype.getBounds=function(){"
    ~ "var xs=[this.p1.x,this.p2.x,this.p3.x,this.p4.x];"
    ~ "var ys=[this.p1.y,this.p2.y,this.p3.y,this.p4.y];"
    ~ "var minX=Math.min.apply(null,xs),maxX=Math.max.apply(null,xs);"
    ~ "var minY=Math.min.apply(null,ys),maxY=Math.max.apply(null,ys);"
    ~ "return new DOMRect(minX,minY,maxX-minX,maxY-minY);"
    ~ "};"
    ~ "}"
    ~ "if(typeof globalThis.DOMMatrixReadOnly==='undefined'){"
    ~ "globalThis.DOMMatrixReadOnly=function DOMMatrixReadOnly(init){"
    ~ "if(Array.isArray(init)&&init.length===6){"
    ~ "this.a=init[0];this.b=init[1];this.c=init[2];this.d=init[3];this.e=init[4];this.f=init[5];this.is2D=true;"
    ~ "}else{this.a=1;this.b=0;this.c=0;this.d=1;this.e=0;this.f=0;this.is2D=true;}"
    ~ "this.isIdentity=this.a===1&&this.b===0&&this.c===0&&this.d===1&&this.e===0&&this.f===0;"
    ~ "};"
    ~ "globalThis.DOMMatrix=function DOMMatrix(init){DOMMatrixReadOnly.call(this,init);};"
    ~ "DOMMatrix.prototype=Object.create(DOMMatrixReadOnly.prototype);"
    ~ "DOMMatrix.prototype.constructor=DOMMatrix;"
    ~ "}"

    // ═══════════════════════════════════
    // ImageData — pixel buffer (Canvas API). Constructor accepts
    // either (w,h) or (Uint8ClampedArray,w[,h]). Used by libraries
    // that synthesise canvas-bound data without a real DOM.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.ImageData==='undefined'){"
    ~ "globalThis.ImageData=function ImageData(a,b,c){"
    ~ "if(a instanceof Uint8ClampedArray){"
    ~ "this.data=a;this.width=b;this.height=c||(a.length/(4*b));"
    ~ "}else{"
    ~ "this.width=a;this.height=b;this.data=new Uint8ClampedArray(a*b*4);"
    ~ "}"
    ~ "this.colorSpace='srgb';"
    ~ "};"
    ~ "}"

    // ═══════════════════════════════════
    // CryptoKey / SubtleCrypto types — handed to / from
    // `crypto.subtle.*`. Plain marker classes for `instanceof` checks.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.CryptoKey==='undefined'){"
    ~ "globalThis.CryptoKey=function CryptoKey(){};"
    ~ "}"
    ~ "if(typeof globalThis.SubtleCrypto==='undefined'){"
    ~ "globalThis.SubtleCrypto=function SubtleCrypto(){};"
    ~ "if(typeof crypto!=='undefined'&&crypto.subtle){"
    ~ "Object.setPrototypeOf(crypto.subtle,SubtleCrypto.prototype);"
    ~ "}"
    ~ "}"

    // ═══════════════════════════════════
    // Stream controller / reader classes — needed for `instanceof`
    // checks in libraries (e.g. cross-fetch). The instances we hand
    // out from `getReader()` / `enqueue` are already shape-compatible;
    // these are the named classes.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.ReadableStreamDefaultReader==='undefined'){"
    ~ "globalThis.ReadableStreamDefaultReader=function ReadableStreamDefaultReader(){};"
    ~ "}"
    ~ "if(typeof globalThis.ReadableStreamBYOBReader==='undefined'){"
    ~ "globalThis.ReadableStreamBYOBReader=function ReadableStreamBYOBReader(){};"
    ~ "}"
    ~ "if(typeof globalThis.ReadableByteStreamController==='undefined'){"
    ~ "globalThis.ReadableByteStreamController=function ReadableByteStreamController(){};"
    ~ "}"
    ~ "if(typeof globalThis.WritableStreamDefaultWriter==='undefined'){"
    ~ "globalThis.WritableStreamDefaultWriter=function WritableStreamDefaultWriter(){};"
    ~ "}"
    ~ "if(typeof globalThis.WritableStreamDefaultController==='undefined'){"
    ~ "globalThis.WritableStreamDefaultController=function WritableStreamDefaultController(){};"
    ~ "}"
    ~ "if(typeof globalThis.TransformStreamDefaultController==='undefined'){"
    ~ "globalThis.TransformStreamDefaultController=function TransformStreamDefaultController(){};"
    ~ "}"

    // ═══════════════════════════════════
    // PerformanceObserver — minimal observer over the `performance`
    // mark/measure entries. Real spec includes resource-timing,
    // navigation-timing etc. that we don't model; this covers the
    // mark/measure subset that monitoring libraries use.
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.PerformanceObserver==='undefined'){"
    ~ "var _perfObservers=[];"
    ~ "globalThis.PerformanceObserver=function PerformanceObserver(cb){this._cb=cb;this._types=[];};"
    ~ "PerformanceObserver.prototype.observe=function(opts){"
    ~ "this._types=opts&&opts.entryTypes?opts.entryTypes:(opts&&opts.type?[opts.type]:[]);"
    ~ "if(_perfObservers.indexOf(this)===-1)_perfObservers.push(this);"
    ~ "};"
    ~ "PerformanceObserver.prototype.disconnect=function(){"
    ~ "var i=_perfObservers.indexOf(this);if(i!==-1)_perfObservers.splice(i,1);"
    ~ "};"
    ~ "PerformanceObserver.prototype.takeRecords=function(){return [];};"
    ~ "PerformanceObserver.supportedEntryTypes=['mark','measure','resource'];"
    ~ "/* hook into performance.mark/measure to feed observers */"
    ~ "if(typeof performance!=='undefined'){"
    ~ "var _origMark=performance.mark;var _origMeasure=performance.measure;"
    ~ "if(_origMark)performance.mark=function(name,opts){"
    ~ "var r=_origMark.apply(this,arguments);"
    ~ "var entry={name:name,entryType:'mark',startTime:performance.now(),duration:0};"
    ~ "for(var i=0;i<_perfObservers.length;i++){"
    ~ "if(_perfObservers[i]._types.indexOf('mark')!==-1){"
    ~ "try{_perfObservers[i]._cb({getEntries:function(){return [entry];},getEntriesByName:function(n){return n===name?[entry]:[];},getEntriesByType:function(t){return t==='mark'?[entry]:[];}});}catch(e){}"
    ~ "}}"
    ~ "return r;"
    ~ "};"
    ~ "}}"

    // ═══════════════════════════════════
    // console.time/timeEnd/timeLog/count/countReset/table
    // ═══════════════════════════════════
    ~ "var _timers={},_counters={};"
    ~ "console.time=function(label){label=label||'default';_timers[label]=Date.now();};"
    ~ "console.timeEnd=function(label){label=label||'default';var start=_timers[label];if(start!==undefined){console.log(label+': '+(Date.now()-start)+'ms');delete _timers[label];}else console.warn('Timer \"'+label+'\" does not exist');};"
    ~ "console.timeLog=function(label){label=label||'default';var start=_timers[label];if(start!==undefined){var args=[label+': '+(Date.now()-start)+'ms'];for(var i=1;i<arguments.length;i++)args.push(arguments[i]);console.log.apply(console,args);}else console.warn('Timer \"'+label+'\" does not exist');};"
    ~ "console.count=function(label){label=label||'default';_counters[label]=(_counters[label]||0)+1;console.log(label+': '+_counters[label]);};"
    ~ "console.countReset=function(label){label=label||'default';_counters[label]=0;};"
    ~ "console.table=function(data){if(Array.isArray(data)){console.log('(index)','Value');for(var i=0;i<data.length;i++)console.log(i,data[i]);}"
    ~ "else if(typeof data==='object'&&data!==null){var keys=Object.keys(data);console.log('(index)','Values');for(var i=0;i<keys.length;i++)console.log(keys[i],data[keys[i]]);}"
    ~ "else console.log(data);};"
    ~ "console.dir=console.dir||function(obj){console.log(typeof __dun_inspect__==='function'?__dun_inspect__(obj):JSON.stringify(obj,null,2));};"
    ~ "console.trace=console.trace||function(){var e=new Error();console.log('Trace'+(arguments.length?': '+[].join.call(arguments,' '):''));if(e.stack)console.log(e.stack.split('\\n').slice(1).join('\\n'));};"
    ~ "console.clear=console.clear||function(){if(typeof process!=='undefined'&&process.stdout&&process.stdout.write)process.stdout.write('\\x1b[2J\\x1b[H');};"
    ~ "var _groupDepth=0;"
    ~ "var _origLog=console.log,_origWarn=console.warn,_origError=console.error,_origInfo=console.info,_origDebug=console.debug;"
    ~ "function _indented(fn){return function(){var prefix='';for(var i=0;i<_groupDepth;i++)prefix+='  ';"
    ~   "if(prefix&&arguments.length>0){var args=[].slice.call(arguments);if(typeof args[0]==='string')args[0]=prefix+args[0];else{args.unshift(prefix);}fn.apply(console,args);}else fn.apply(console,arguments);};"
    ~ "}"
    ~ "console.group=function(){if(arguments.length>0){var fn=_indented(_origLog);fn.apply(console,arguments);}_groupDepth++;};"
    ~ "console.groupEnd=function(){if(_groupDepth>0)_groupDepth--;};"
    ~ "console.groupCollapsed=console.group;"
    ~ "console.log=_indented(_origLog);console.warn=_indented(_origWarn);console.error=_indented(_origError);"
    ~ "console.info=_indented(_origInfo);console.debug=_indented(_origDebug);"

    // TypedArray.from/of polyfills (some QuickJS builds miss static methods)
    ~ "['Int8Array','Uint8Array','Uint8ClampedArray','Int16Array','Uint16Array','Int32Array','Uint32Array','Float32Array','Float64Array'].forEach(function(name){"
    ~   "var C=globalThis[name];if(!C)return;"
    ~   "if(!C.from)C.from=function(src,mapFn,thisArg){var arr=Array.isArray(src)?src:Array.from(src);"
    ~     "if(mapFn){for(var j=0;j<arr.length;j++)arr[j]=mapFn.call(thisArg,arr[j],j);}return new C(arr);};"
    ~   "if(!C.of)C.of=function(){return new C([].slice.call(arguments));};"
    ~ "});"

    ~ "})();";
    static assert(src.length > 0, "webAPIsSource must not be empty");
    return src;
}
