module dun.builtins.tls;

version (Posix):

import dun.platform.openssl;

private __gshared SSL_CTX* gClientCtx;
private __gshared bool gInitDone;

void ensureTlsInit() @trusted nothrow @nogc
{
    if (gInitDone) return;
    OPENSSL_init_ssl(
        OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);

    gClientCtx = SSL_CTX_new(TLS_client_method());
    if (gClientCtx)
    {
        SSL_CTX_set_default_verify_paths(gClientCtx);
        SSL_CTX_set_verify(gClientCtx, SSL_VERIFY_PEER, null);
        SSL_CTX_ctrl(gClientCtx, SSL_CTRL_SET_MIN_PROTO_VERSION,
            TLS1_2_VERSION, null);
    }
    gInitDone = true;
}

struct TlsSocket
{
    SSL* ssl;
    int fd = -1;

    @disable this(this);

    bool connect(int sockFd, const(char)* hostname) @trusted nothrow @nogc
    {
        ensureTlsInit();
        if (!gClientCtx) return false;

        ssl = SSL_new(gClientCtx);
        if (!ssl) return false;
        fd = sockFd;

        SSL_set_fd(ssl, fd);

        // SNI
        SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME,
            TLSEXT_NAMETYPE_host_name, cast(void*) hostname);

        // hostname verification (OpenSSL 1.1+)
        SSL_set1_host(ssl, hostname);

        ERR_clear_error();
        int ret = SSL_connect(ssl);
        return ret == 1;
    }

    int read(void* buf, int len) @trusted nothrow @nogc
    {
        if (!ssl) return -1;
        return SSL_read(ssl, buf, len);
    }

    int write(const(void)* buf, int len) @trusted nothrow @nogc
    {
        if (!ssl) return -1;
        return SSL_write(ssl, buf, len);
    }

    void close() @trusted nothrow @nogc
    {
        if (ssl)
        {
            SSL_shutdown(ssl);
            SSL_free(ssl);
            ssl = null;
        }
        if (fd >= 0)
        {
            import core.sys.posix.unistd : posixClose = close;
            posixClose(fd);
            fd = -1;
        }
    }

    ~this() @trusted nothrow @nogc
    {
        close();
    }
}

string tlsLastError() @trusted nothrow
{
    auto e = ERR_peek_last_error();
    if (e == 0) return "unknown TLS error";
    auto s = ERR_reason_error_string(e);
    if (!s) return "unknown TLS error";
    size_t len = 0;
    while (s[len] != 0) len++;
    try { return (cast(const(char)*) s)[0 .. len].idup; }
    catch (Throwable) { return "unknown TLS error"; }
}
