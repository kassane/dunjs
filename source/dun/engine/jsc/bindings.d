module dun.engine.jsc.bindings;

// --- Opaque handle types (WebKit JavaScriptCore C API) ---
struct OpaqueJSContextGroup;
struct OpaqueJSContext;
struct OpaqueJSValue;
struct OpaqueJSString;
struct OpaqueJSClass;
struct OpaqueJSPropertyNameArray;

alias JSContextGroupRef = OpaqueJSContextGroup*;
alias JSGlobalContextRef = OpaqueJSContext*;
alias JSContextRef = const(OpaqueJSContext)*;
alias JSValueRef = const(OpaqueJSValue)*;
alias JSObjectRef = OpaqueJSValue*;
alias JSStringRef = OpaqueJSString*;
alias JSClassRef = OpaqueJSClass*;
alias JSPropertyNameArrayRef = OpaqueJSPropertyNameArray*;

// --- Property attributes ---
alias JSPropertyAttributes = uint;
enum : JSPropertyAttributes
{
    kJSPropertyAttributeNone = 0,
    kJSPropertyAttributeReadOnly = 1 << 1,
    kJSPropertyAttributeDontEnum = 1 << 2,
    kJSPropertyAttributeDontDelete = 1 << 3,
}

// --- JSType enum ---
alias JSType = uint;
enum : JSType
{
    kJSTypeUndefined = 0,
    kJSTypeNull = 1,
    kJSTypeBoolean = 2,
    kJSTypeNumber = 3,
    kJSTypeString = 4,
    kJSTypeObject = 5,
    kJSTypeSymbol = 6,
}

// --- Callback types ---
alias JSObjectInitializeCallback = extern (C) void function(
    JSContextRef ctx, JSObjectRef object) nothrow;

alias JSObjectFinalizeCallback = extern (C) void function(
    JSObjectRef object) nothrow;

alias JSObjectCallAsFunctionCallback = extern (C) JSValueRef function(
    JSContextRef ctx, JSObjectRef func, JSObjectRef thisObject,
    size_t argumentCount, const(JSValueRef)* arguments,
    JSValueRef* exception) nothrow;

alias JSObjectCallAsConstructorCallback = extern (C) JSObjectRef function(
    JSContextRef ctx, JSObjectRef constructor,
    size_t argumentCount, const(JSValueRef)* arguments,
    JSValueRef* exception) nothrow;

alias JSObjectHasPropertyCallback = extern (C) bool function(
    JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName) nothrow;

alias JSObjectGetPropertyCallback = extern (C) JSValueRef function(
    JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName, JSValueRef* exception) nothrow;

alias JSObjectSetPropertyCallback = extern (C) bool function(
    JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName, JSValueRef value,
    JSValueRef* exception) nothrow;

// --- Class definition ---
struct JSStaticFunction
{
    const(char)* name;
    JSObjectCallAsFunctionCallback callAsFunction;
    JSPropertyAttributes attributes;
}

struct JSStaticValue
{
    const(char)* name;
    JSObjectGetPropertyCallback getProperty;
    JSObjectSetPropertyCallback setProperty;
    JSPropertyAttributes attributes;
}

struct JSClassDefinition
{
    int version_;
    uint attributes;
    const(char)* className;
    JSClassRef parentClass;
    const(JSStaticValue)* staticValues;
    const(JSStaticFunction)* staticFunctions;
    JSObjectInitializeCallback initialize;
    JSObjectFinalizeCallback finalize;
    JSObjectHasPropertyCallback hasProperty;
    JSObjectGetPropertyCallback getProperty;
    JSObjectSetPropertyCallback setProperty;
    void* deleteProperty;
    void* getPropertyNames;
    JSObjectCallAsFunctionCallback callAsFunction;
    JSObjectCallAsConstructorCallback callAsConstructor;
    void* hasInstance;
    void* convertToType;
}

// ==========================================================================
// JavaScriptCore C API functions
// ==========================================================================
extern (C) nothrow @nogc:

// --- Context group ---
JSContextGroupRef JSContextGroupCreate();
JSContextGroupRef JSContextGroupRetain(JSContextGroupRef group);
void JSContextGroupRelease(JSContextGroupRef group);

// --- Global context ---
JSGlobalContextRef JSGlobalContextCreate(JSClassRef globalObjectClass);
JSGlobalContextRef JSGlobalContextCreateInGroup(
    JSContextGroupRef group, JSClassRef globalObjectClass);
JSGlobalContextRef JSGlobalContextRetain(JSGlobalContextRef ctx);
void JSGlobalContextRelease(JSGlobalContextRef ctx);

// --- Context ---
JSObjectRef JSContextGetGlobalObject(JSContextRef ctx);
JSContextGroupRef JSContextGetGroup(JSContextRef ctx);
JSGlobalContextRef JSContextGetGlobalContext(JSContextRef ctx);

// --- Script evaluation ---
JSValueRef JSEvaluateScript(JSContextRef ctx, JSStringRef script,
    JSObjectRef thisObject, JSStringRef sourceURL,
    int startingLineNumber, JSValueRef* exception);

bool JSCheckScriptSyntax(JSContextRef ctx, JSStringRef script,
    JSStringRef sourceURL, int startingLineNumber,
    JSValueRef* exception);

// --- Garbage collection ---
void JSGarbageCollect(JSContextRef ctx);

// --- String ---
JSStringRef JSStringCreateWithUTF8CString(const(char)* string);
JSStringRef JSStringRetain(JSStringRef string);
void JSStringRelease(JSStringRef string);
size_t JSStringGetLength(JSStringRef string);
size_t JSStringGetMaximumUTF8CStringSize(JSStringRef string);
size_t JSStringGetUTF8CString(JSStringRef string, char* buffer, size_t bufferSize);
bool JSStringIsEqual(JSStringRef a, JSStringRef b);
bool JSStringIsEqualToUTF8CString(JSStringRef a, const(char)* b);

// --- Value type checks ---
JSType JSValueGetType(JSContextRef ctx, JSValueRef value);
bool JSValueIsUndefined(JSContextRef ctx, JSValueRef value);
bool JSValueIsNull(JSContextRef ctx, JSValueRef value);
bool JSValueIsBoolean(JSContextRef ctx, JSValueRef value);
bool JSValueIsNumber(JSContextRef ctx, JSValueRef value);
bool JSValueIsString(JSContextRef ctx, JSValueRef value);
bool JSValueIsSymbol(JSContextRef ctx, JSValueRef value);
bool JSValueIsObject(JSContextRef ctx, JSValueRef value);
bool JSValueIsArray(JSContextRef ctx, JSValueRef value);
bool JSValueIsDate(JSContextRef ctx, JSValueRef value);
bool JSValueIsObjectOfClass(JSContextRef ctx, JSValueRef value, JSClassRef jsClass);

// --- Value creation ---
JSValueRef JSValueMakeUndefined(JSContextRef ctx);
JSValueRef JSValueMakeNull(JSContextRef ctx);
JSValueRef JSValueMakeBoolean(JSContextRef ctx, bool boolean);
JSValueRef JSValueMakeNumber(JSContextRef ctx, double number);
JSValueRef JSValueMakeString(JSContextRef ctx, JSStringRef string);

// --- Value conversion ---
bool JSValueToBoolean(JSContextRef ctx, JSValueRef value);
double JSValueToNumber(JSContextRef ctx, JSValueRef value, JSValueRef* exception);
JSStringRef JSValueToStringCopy(JSContextRef ctx, JSValueRef value, JSValueRef* exception);
JSObjectRef JSValueToObject(JSContextRef ctx, JSValueRef value, JSValueRef* exception);

// --- Value comparison ---
bool JSValueIsEqual(JSContextRef ctx, JSValueRef a, JSValueRef b, JSValueRef* exception);
bool JSValueIsStrictEqual(JSContextRef ctx, JSValueRef a, JSValueRef b);

// --- Value protect/unprotect (prevent GC) ---
void JSValueProtect(JSContextRef ctx, JSValueRef value);
void JSValueUnprotect(JSContextRef ctx, JSValueRef value);

// --- Object creation ---
JSObjectRef JSObjectMake(JSContextRef ctx, JSClassRef jsClass, void* data);
JSObjectRef JSObjectMakeFunctionWithCallback(JSContextRef ctx,
    JSStringRef name, JSObjectCallAsFunctionCallback callAsFunction);
JSObjectRef JSObjectMakeConstructor(JSContextRef ctx, JSClassRef jsClass,
    JSObjectCallAsConstructorCallback callAsConstructor);
JSObjectRef JSObjectMakeArray(JSContextRef ctx, size_t argumentCount,
    const(JSValueRef)* arguments, JSValueRef* exception);
JSObjectRef JSObjectMakeError(JSContextRef ctx, size_t argumentCount,
    const(JSValueRef)* arguments, JSValueRef* exception);
JSObjectRef JSObjectMakeDeferredPromise(JSContextRef ctx,
    JSObjectRef* resolve, JSObjectRef* reject, JSValueRef* exception);

// --- Object property access ---
bool JSObjectHasProperty(JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName);
JSValueRef JSObjectGetProperty(JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName, JSValueRef* exception);
void JSObjectSetProperty(JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName, JSValueRef value,
    JSPropertyAttributes attributes, JSValueRef* exception);
bool JSObjectDeleteProperty(JSContextRef ctx, JSObjectRef object,
    JSStringRef propertyName, JSValueRef* exception);

// --- Object indexed access ---
JSValueRef JSObjectGetPropertyAtIndex(JSContextRef ctx, JSObjectRef object,
    uint propertyIndex, JSValueRef* exception);
void JSObjectSetPropertyAtIndex(JSContextRef ctx, JSObjectRef object,
    uint propertyIndex, JSValueRef value, JSValueRef* exception);

// --- Object private data ---
void* JSObjectGetPrivate(JSObjectRef object);
bool JSObjectSetPrivate(JSObjectRef object, void* data);

// --- Object as function ---
bool JSObjectIsFunction(JSContextRef ctx, JSObjectRef object);
JSValueRef JSObjectCallAsFunction(JSContextRef ctx, JSObjectRef object,
    JSObjectRef thisObject, size_t argumentCount,
    const(JSValueRef)* arguments, JSValueRef* exception);

// --- Object as constructor ---
bool JSObjectIsConstructor(JSContextRef ctx, JSObjectRef object);
JSObjectRef JSObjectCallAsConstructor(JSContextRef ctx, JSObjectRef object,
    size_t argumentCount, const(JSValueRef)* arguments,
    JSValueRef* exception);

// --- Property names ---
JSPropertyNameArrayRef JSObjectCopyPropertyNames(JSContextRef ctx, JSObjectRef object);
size_t JSPropertyNameArrayGetCount(JSPropertyNameArrayRef array);
JSStringRef JSPropertyNameArrayGetNameAtIndex(JSPropertyNameArrayRef array, size_t index);
void JSPropertyNameArrayRelease(JSPropertyNameArrayRef array);

// --- Class ---
JSClassRef JSClassCreate(const(JSClassDefinition)* definition);
JSClassRef JSClassRetain(JSClassRef jsClass);
void JSClassRelease(JSClassRef jsClass);

// --- Typed arrays (JSC 10.12+ / WebKitGTK 2.14+) ---
enum JSTypedArrayType : uint
{
    kJSTypedArrayTypeInt8Array = 0,
    kJSTypedArrayTypeInt16Array = 1,
    kJSTypedArrayTypeInt32Array = 2,
    kJSTypedArrayTypeUint8Array = 3,
    kJSTypedArrayTypeUint8ClampedArray = 4,
    kJSTypedArrayTypeUint16Array = 5,
    kJSTypedArrayTypeUint32Array = 6,
    kJSTypedArrayTypeFloat32Array = 7,
    kJSTypedArrayTypeFloat64Array = 8,
    kJSTypedArrayTypeArrayBuffer = 9,
    kJSTypedArrayTypeNone = 10,
}

alias JSTypedArrayBytesDeallocator = extern (C) void function(
    void* bytes, void* deallocatorContext) nothrow;

JSObjectRef JSObjectMakeTypedArray(JSContextRef ctx,
    JSTypedArrayType arrayType, size_t length, JSValueRef* exception);
JSObjectRef JSObjectMakeTypedArrayWithBytesNoCopy(JSContextRef ctx,
    JSTypedArrayType arrayType, void* bytes, size_t byteLength,
    JSTypedArrayBytesDeallocator bytesDeallocator,
    void* deallocatorContext, JSValueRef* exception);
JSObjectRef JSObjectMakeArrayBufferWithBytesNoCopy(JSContextRef ctx,
    void* bytes, size_t byteLength,
    JSTypedArrayBytesDeallocator bytesDeallocator,
    void* deallocatorContext, JSValueRef* exception);
void* JSObjectGetTypedArrayBytesPtr(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
size_t JSObjectGetTypedArrayLength(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
size_t JSObjectGetTypedArrayByteLength(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
size_t JSObjectGetTypedArrayByteOffset(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
JSObjectRef JSObjectGetTypedArrayBuffer(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
void* JSObjectGetArrayBufferBytesPtr(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
size_t JSObjectGetArrayBufferByteLength(JSContextRef ctx,
    JSObjectRef object, JSValueRef* exception);
