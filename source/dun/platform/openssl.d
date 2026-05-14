module dun.platform.openssl;

version (Posix):

// Minimal extern(C) bindings for OpenSSL 1.1+ / 3.x (libssl + libcrypto).
// Only the subset needed for TLS client sockets and HTTPS fetch.

extern (C) nothrow @nogc:

// --- Opaque types ---

struct SSL;
struct SSL_CTX;
struct SSL_METHOD;
struct BIO;
struct BIO_METHOD;
struct X509_STORE_CTX;

// --- Library init (OpenSSL 1.1+ auto-initializes, but explicit is safer) ---

int OPENSSL_init_ssl(ulong opts, void* settings);
int OPENSSL_init_crypto(ulong opts, void* settings);

enum : ulong
{
    OPENSSL_INIT_LOAD_SSL_STRINGS = 0x0020_0000,
    OPENSSL_INIT_LOAD_CRYPTO_STRINGS = 0x0000_0002,
    OPENSSL_INIT_ADD_ALL_CIPHERS = 0x0000_0004,
    OPENSSL_INIT_ADD_ALL_DIGESTS = 0x0000_0008,
}

// --- SSL_METHOD ---

const(SSL_METHOD)* TLS_client_method();
const(SSL_METHOD)* TLS_method();

// --- SSL_CTX ---

SSL_CTX* SSL_CTX_new(const(SSL_METHOD)* meth);
void SSL_CTX_free(SSL_CTX* ctx);
int SSL_CTX_set_default_verify_paths(SSL_CTX* ctx);
void SSL_CTX_set_verify(SSL_CTX* ctx, int mode, void* callback);

enum SSL_VERIFY_NONE = 0x00;
enum SSL_VERIFY_PEER = 0x01;

long SSL_CTX_set_options(SSL_CTX* ctx, long options);

enum : long
{
    SSL_OP_NO_SSLv2 = 0x0100_0000,
    SSL_OP_NO_SSLv3 = 0x0200_0000,
}

long SSL_CTX_ctrl(SSL_CTX* ctx, int cmd, long larg, void* parg);

enum SSL_CTRL_SET_MIN_PROTO_VERSION = 123;
enum SSL_CTRL_SET_MAX_PROTO_VERSION = 124;
enum TLS1_2_VERSION = 0x0303;
enum TLS1_3_VERSION = 0x0304;

// --- SSL ---

SSL* SSL_new(SSL_CTX* ctx);
void SSL_free(SSL* ssl);
int SSL_set_fd(SSL* ssl, int fd);
int SSL_connect(SSL* ssl);
int SSL_read(SSL* ssl, void* buf, int num);
int SSL_write(SSL* ssl, const(void)* buf, int num);
int SSL_shutdown(SSL* ssl);

int SSL_get_error(const(SSL)* ssl, int ret);

enum
{
    SSL_ERROR_NONE = 0,
    SSL_ERROR_SSL = 1,
    SSL_ERROR_WANT_READ = 2,
    SSL_ERROR_WANT_WRITE = 3,
    SSL_ERROR_WANT_X509_LOOKUP = 4,
    SSL_ERROR_SYSCALL = 5,
    SSL_ERROR_ZERO_RETURN = 6,
    SSL_ERROR_WANT_CONNECT = 7,
    SSL_ERROR_WANT_ACCEPT = 8,
}

// SNI (Server Name Indication) — required for most HTTPS servers
enum SSL_CTRL_SET_TLSEXT_HOSTNAME = 55;
enum TLSEXT_NAMETYPE_host_name = 0;
long SSL_ctrl(SSL* ssl, int cmd, long larg, void* parg);

// --- ERR ---

ulong ERR_get_error();
ulong ERR_peek_last_error();
void ERR_clear_error();
const(char)* ERR_reason_error_string(ulong e);

// --- SSL server ---

int SSL_accept(SSL* ssl);

// Certificate loading (server-side TLS)
int SSL_CTX_use_certificate_file(SSL_CTX* ctx, const(char)* file, int type);
int SSL_CTX_use_PrivateKey_file(SSL_CTX* ctx, const(char)* file, int type);
int SSL_CTX_check_private_key(const(SSL_CTX)* ctx);

enum SSL_FILETYPE_PEM = 1;
enum SSL_FILETYPE_ASN1 = 2;

// --- ALPN (Application Layer Protocol Negotiation) ---

int SSL_CTX_set_alpn_protos(SSL_CTX* ctx, const(ubyte)* protos, uint protos_len);
int SSL_set_alpn_protos(SSL* ssl, const(ubyte)* protos, uint protos_len);
void SSL_get0_alpn_selected(const(SSL)* ssl, const(ubyte)** data, uint* len);

alias SSL_CTX_alpn_select_cb_func = extern(C) int function(
    SSL* ssl, const(ubyte)** out_, ubyte* outlen,
    const(ubyte)* in_, uint inlen, void* arg) nothrow;
void SSL_CTX_set_alpn_select_cb(SSL_CTX* ctx, SSL_CTX_alpn_select_cb_func cb, void* arg);

int SSL_select_next_proto(
    ubyte** out_, ubyte* outlen,
    const(ubyte)* server, uint server_len,
    const(ubyte)* client, uint client_len);

enum OPENSSL_NPN_NEGOTIATED = 1;
enum OPENSSL_NPN_NO_OVERLAP = 2;

// --- Pending data ---

int SSL_pending(const(SSL)* ssl);
int SSL_has_pending(const(SSL)* ssl);

// --- Cipher info ---

const(char)* SSL_CIPHER_get_name(const(void)* cipher);
void* SSL_get_ciphers(const(SSL)* ssl);
int OPENSSL_sk_num(const(void)* stack);
void* OPENSSL_sk_value(const(void)* stack, int idx);

// --- BIO (for hostname verification) ---

int SSL_set1_host(SSL* ssl, const(char)* hostname);
