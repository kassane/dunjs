module dun.runtime.web_apis;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;

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

    bindNativeCryptoOnGlobal(engine);
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
    assert(ctx !is null, "Null ctx in getRandomValues");
    auto state = cast(DunState*) ctx;
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
       Request body), drain it to text. Otherwise toString it. */
    ~ "Response.prototype.text=function(){"
    ~   "this.bodyUsed=true;"
    ~   "var b=this._body;"
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
       otherwise fall back to the toString-encode path. */
    ~ "Response.prototype.arrayBuffer=function(){"
    ~   "this.bodyUsed=true;"
    ~   "var b=this._body;"
    ~   "if(b instanceof ArrayBuffer)return Promise.resolve(b);"
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
    // MessageChannel / MessagePort
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
    ~ "MessagePort.prototype.onmessage=null;"

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
    // crypto.getRandomValues()
    // ═══════════════════════════════════
    ~ "if(typeof globalThis.crypto==='undefined')globalThis.crypto={};"

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
