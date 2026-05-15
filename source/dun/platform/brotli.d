module dun.platform.brotli;

// extern(C) bindings for libbrotli (libbrotlienc / libbrotlidec).
// Only the one-shot compress/decompress entry points are needed for sync APIs.
// Streaming APIs are layered in JS via async wrappers around the sync core.

extern (C) nothrow @nogc:

enum BROTLI_MODE_GENERIC = 0;
enum BROTLI_MODE_TEXT = 1;
enum BROTLI_MODE_FONT = 2;

enum BROTLI_DEFAULT_QUALITY = 11;
enum BROTLI_DEFAULT_WINDOW = 22;
enum BROTLI_MIN_QUALITY = 0;
enum BROTLI_MAX_QUALITY = 11;
enum BROTLI_MIN_WINDOW_BITS = 10;
enum BROTLI_MAX_WINDOW_BITS = 24;

enum BROTLI_DECODER_RESULT_ERROR = 0;
enum BROTLI_DECODER_RESULT_SUCCESS = 1;
enum BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT = 2;
enum BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT = 3;

alias BROTLI_BOOL = int;
alias BrotliEncoderMode = int;
alias BrotliDecoderResult = int;

size_t BrotliEncoderMaxCompressedSize(size_t input_size);

BROTLI_BOOL BrotliEncoderCompress(
    int quality,
    int lgwin,
    BrotliEncoderMode mode,
    size_t input_size,
    const(ubyte)* input_buffer,
    size_t* encoded_size,
    ubyte* encoded_buffer);

BrotliDecoderResult BrotliDecoderDecompress(
    size_t encoded_size,
    const(ubyte)* encoded_buffer,
    size_t* decoded_size,
    ubyte* decoded_buffer);

uint BrotliEncoderVersion();
uint BrotliDecoderVersion();

// Streaming decoder
struct BrotliDecoderState;
alias brotli_alloc_func = void* function(void*, size_t);
alias brotli_free_func = void function(void*, void*);

BrotliDecoderState* BrotliDecoderCreateInstance(
    brotli_alloc_func alloc_func,
    brotli_free_func free_func,
    void* opaque);

void BrotliDecoderDestroyInstance(BrotliDecoderState* state);

BrotliDecoderResult BrotliDecoderDecompressStream(
    BrotliDecoderState* state,
    size_t* available_in,
    const(ubyte)** next_in,
    size_t* available_out,
    ubyte** next_out,
    size_t* total_out);

BROTLI_BOOL BrotliDecoderIsFinished(const(BrotliDecoderState)* state);
BROTLI_BOOL BrotliDecoderHasMoreOutput(const(BrotliDecoderState)* state);
const(ubyte)* BrotliDecoderTakeOutput(BrotliDecoderState* state, size_t* size);
