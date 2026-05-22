module dun.platform.lsquic;


/// `@trusted policy`: lsquic FFI declarations (extern(C) function
/// declarations for QUIC engine init / send / recv / connection
/// management). Wrapped from `dun.builtins.http3`.
// extern(C) bindings to lsquic — QUIC/HTTP3 library (litespeedtech/lsquic).
// Only the subset needed for HTTP/3 server and client.

struct lsquic_engine;
struct lsquic_conn;
struct lsquic_stream;
struct lsquic_conn_ctx;
struct lsquic_stream_ctx;
struct lsquic_out_spec;

alias lsquic_engine_t = lsquic_engine;
alias lsquic_conn_t = lsquic_conn;
alias lsquic_stream_t = lsquic_stream;
alias lsquic_conn_ctx_t = lsquic_conn_ctx;
alias lsquic_stream_ctx_t = lsquic_stream_ctx;

// Engine flags
enum LSENG_SERVER = 1;
enum LSENG_HTTP   = 2;

// QUIC versions
enum lsquic_version
{
    LSQVER_043  = 0,
    LSQVER_046  = 1,
    LSQVER_050  = 2,
    LSQVER_I001 = 3, // QUIC v1 (RFC 9000)
    LSQVER_I002 = 4, // QUIC v2 (RFC 9369)
    N_LSQVER    = 5,
}

// Stream callback interface — user implements these
struct lsquic_stream_if
{
    extern(C) lsquic_conn_ctx_t* function(void* stream_if_ctx,
        lsquic_conn_t* conn) nothrow on_new_conn;
    extern(C) void function(lsquic_conn_t* conn) nothrow on_conn_closed;
    extern(C) lsquic_stream_ctx_t* function(void* stream_if_ctx,
        lsquic_stream_t* stream) nothrow on_new_stream;
    extern(C) void function(lsquic_stream_t* stream,
        lsquic_stream_ctx_t* ctx) nothrow on_read;
    extern(C) void function(lsquic_stream_t* stream,
        lsquic_stream_ctx_t* ctx) nothrow on_write;
    extern(C) void function(lsquic_stream_t* stream,
        lsquic_stream_ctx_t* ctx) nothrow on_close;
    extern(C) void function(lsquic_stream_t* stream,
        lsquic_stream_ctx_t* ctx) nothrow on_goaway_received;
    extern(C) void function(lsquic_stream_t* stream,
        lsquic_stream_ctx_t* ctx) nothrow on_conncloseframe_received;
}

// Packets out callback
alias lsquic_packets_out_f = extern(C) int function(void* packets_out_ctx,
    const(lsquic_out_spec)* out_spec, uint n_packets_out) nothrow;

// HTTP header
struct lsquic_http_header
{
    // iovec-like name/value pairs
    struct lsxpack_header;
}

struct lsquic_http_headers
{
    int count;
    lsquic_http_header* headers;
}

// Engine API structure
struct lsquic_engine_api
{
    const(lsquic_stream_if)* ea_stream_if;
    void*                    ea_stream_if_ctx;
    lsquic_packets_out_f     ea_packets_out;
    void*                    ea_packets_out_ctx;
    // Additional fields exist but are optional
}

// Engine settings
struct lsquic_engine_settings
{
    uint es_versions;    // Bitmask of supported versions
    uint es_cfcw;        // Connection flow control window
    uint es_sfcw;        // Stream flow control window
    uint es_max_streams_in;
    ulong es_init_max_data;
    ulong es_init_max_stream_data_bidi_local;
    ulong es_init_max_stream_data_bidi_remote;
    ulong es_init_max_stream_data_uni;
    ulong es_max_header_list_size;
    // Many more fields exist — this covers the essentials
}

extern(C) nothrow @nogc:

// --- Global init/cleanup ---
int lsquic_global_init(int flags);
void lsquic_global_cleanup();

// --- Engine management ---
void lsquic_engine_init_settings(lsquic_engine_settings* settings,
    uint engine_flags);
int lsquic_engine_check_settings(const(lsquic_engine_settings)* settings,
    uint engine_flags, char* err_buf, size_t err_buf_sz);
lsquic_engine_t* lsquic_engine_new(uint engine_flags,
    const(lsquic_engine_api)* api);
void lsquic_engine_destroy(lsquic_engine_t* engine);
void lsquic_engine_process_conns(lsquic_engine_t* engine);
int lsquic_engine_has_unsent_packets(lsquic_engine_t* engine);
void lsquic_engine_send_unsent_packets(lsquic_engine_t* engine);
uint lsquic_engine_count_attq(lsquic_engine_t* engine, int from_now);

// --- Connections ---
lsquic_conn_t* lsquic_engine_connect(lsquic_engine_t* engine,
    lsquic_version ver,
    const(void)* local_sa, const(void)* peer_sa,
    void* peer_ctx, lsquic_conn_ctx_t* conn_ctx,
    const(char)* hostname, ushort base_plpmtu,
    const(ubyte)* sess_resume, size_t sess_resume_len,
    const(ubyte)* token, size_t token_sz);
int lsquic_engine_packet_in(lsquic_engine_t* engine,
    const(ubyte)* packet_data, size_t packet_size,
    const(void)* sa_local, const(void)* sa_peer,
    void* peer_ctx, int ecn);
void lsquic_conn_close(lsquic_conn_t* conn);
void lsquic_conn_abort(lsquic_conn_t* conn);
void lsquic_conn_going_away(lsquic_conn_t* conn);
void lsquic_conn_make_stream(lsquic_conn_t* conn);

// --- Streams ---
ptrdiff_t lsquic_stream_read(lsquic_stream_t* stream, void* buf, size_t len);
ptrdiff_t lsquic_stream_write(lsquic_stream_t* stream,
    const(void)* buf, size_t len);
int lsquic_stream_wantread(lsquic_stream_t* stream, int want);
int lsquic_stream_wantwrite(lsquic_stream_t* stream, int want);
int lsquic_stream_send_headers(lsquic_stream_t* stream,
    const(lsquic_http_headers)* headers, int eos);
int lsquic_stream_shutdown(lsquic_stream_t* stream, int how);
int lsquic_stream_close(lsquic_stream_t* stream);
int lsquic_stream_flush(lsquic_stream_t* stream);
uint lsquic_stream_id(const(lsquic_stream_t)* stream);
int lsquic_stream_is_pushed(const(lsquic_stream_t)* stream);

// --- Logging ---
void lsquic_logger_init(const(void)* logger_if, void* logger_ctx, int style);
int lsquic_set_log_level(const(char)* log_level);
