module dun.builtins.wasi;


/++
 + `@trusted policy`: WebAssembly System Interface (WASI) preview1
 + subset — `args_get`, `environ_get`, `clock_time_get`,
 + `random_get`, `fd_read`/`fd_write`/`fd_close`,
 + `path_open`/`path_create_directory`, etc. Every `@trusted` is
 + one of:
 +   1. POSIX syscalls (same surface as `fs.d`/`net.d`).
 +   2. `engine.getTypedArrayBytes` to access the wasm guest
 +      memory — returns a slice scoped to the JSHandle (DIP1000).
 +   3. `Permission.read` / `Permission.write` gates.
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.builtins.helpers : installPureJsModule;

void registerWasiModule(IJSEngine engine) @trusted
{
    installPureJsModule(engine, wasiSource(), "<wasi>", "wasi");

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in wasi registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:wasi", &wasiModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "WASI");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int wasiModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in wasiModuleInit");
        assert(m !is null, "Null JSModuleDef in wasiModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_wasi__");

        auto wasi = JS_GetPropertyStr(ctx, mod, "WASI");
        JS_SetModuleExport(ctx, m, "WASI", wasi);
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

// WASI preview1 implementation.
//
// Implements the wasi_snapshot_preview1 interface (subset sufficient
// for `wasi-libc` "hello world" and small CLI utilities). The shim
// translates each wasi call into reads/writes on the module's
// linear memory plus the matching host syscall via `dun:fs` and
// `process`.
//
// Errno values, file types and rights bitmasks follow:
//   https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md
string wasiSource() pure @safe nothrow
{
    return `(function() {
  'use strict';

  // WASI errno codes (subset)
  var WASI_ESUCCESS = 0;
  var WASI_E2BIG = 1;
  var WASI_EACCES = 2;
  var WASI_EAGAIN = 6;
  var WASI_EBADF = 8;
  var WASI_EEXIST = 20;
  var WASI_EINVAL = 28;
  var WASI_EIO = 29;
  var WASI_EISDIR = 31;
  var WASI_ENOENT = 44;
  var WASI_ENOSYS = 52;
  var WASI_ENOTDIR = 54;
  var WASI_EPERM = 63;

  // File descriptor types
  var WASI_FILETYPE_UNKNOWN = 0;
  var WASI_FILETYPE_BLOCK_DEVICE = 1;
  var WASI_FILETYPE_CHARACTER_DEVICE = 2;
  var WASI_FILETYPE_DIRECTORY = 3;
  var WASI_FILETYPE_REGULAR_FILE = 4;
  var WASI_FILETYPE_SOCKET_DGRAM = 5;
  var WASI_FILETYPE_SOCKET_STREAM = 6;
  var WASI_FILETYPE_SYMBOLIC_LINK = 7;

  // Preopen types
  var WASI_PREOPENTYPE_DIR = 0;

  // Clock IDs
  var WASI_CLOCK_REALTIME = 0;
  var WASI_CLOCK_MONOTONIC = 1;
  var WASI_CLOCK_PROCESS_CPUTIME_ID = 2;
  var WASI_CLOCK_THREAD_CPUTIME_ID = 3;

  // Right flags (subset)
  var WASI_RIGHT_FD_DATASYNC = 1n << 0n;
  var WASI_RIGHT_FD_READ = 1n << 1n;
  var WASI_RIGHT_FD_SEEK = 1n << 2n;
  var WASI_RIGHT_FD_WRITE = 1n << 6n;
  var WASI_RIGHT_PATH_OPEN = 1n << 13n;
  var WASI_RIGHTS_ALL = ~0n & ((1n << 30n) - 1n);

  // Oflags
  var WASI_O_CREAT = 1 << 0;
  var WASI_O_DIRECTORY = 1 << 1;
  var WASI_O_EXCL = 1 << 2;
  var WASI_O_TRUNC = 1 << 3;

  // Fdflags
  var WASI_FDFLAG_APPEND = 1 << 0;
  var WASI_FDFLAG_DSYNC = 1 << 1;
  var WASI_FDFLAG_NONBLOCK = 1 << 2;
  var WASI_FDFLAG_RSYNC = 1 << 3;
  var WASI_FDFLAG_SYNC = 1 << 4;

  // Whence
  var WASI_WHENCE_SET = 0;
  var WASI_WHENCE_CUR = 1;
  var WASI_WHENCE_END = 2;

  function tryRequire(name) {
    try { return require(name); } catch (_) { return null; }
  }

  function mapNodeErrno(err) {
    if (!err || !err.code) return WASI_EIO;
    switch (err.code) {
      case 'ENOENT': return WASI_ENOENT;
      case 'EBADF': return WASI_EBADF;
      case 'EACCES': return WASI_EACCES;
      case 'EEXIST': return WASI_EEXIST;
      case 'EINVAL': return WASI_EINVAL;
      case 'EISDIR': return WASI_EISDIR;
      case 'ENOTDIR': return WASI_ENOTDIR;
      case 'EPERM': return WASI_EPERM;
      case 'EAGAIN': return WASI_EAGAIN;
      default: return WASI_EIO;
    }
  }

  function WASI(opts) {
    if (!(this instanceof WASI))
      return new WASI(opts);
    opts = opts || {};

    this.args = opts.args || [];
    this.env = opts.env || {};
    this.preopens = opts.preopens || {};
    this.returnOnExit = opts.returnOnExit !== false;
    this.stdin = (typeof opts.stdin === 'number') ? opts.stdin : 0;
    this.stdout = (typeof opts.stdout === 'number') ? opts.stdout : 1;
    this.stderr = (typeof opts.stderr === 'number') ? opts.stderr : 2;

    // Backing fs/process modules (loaded lazily so the wasi module
    // can still be imported in sandboxed environments without fs).
    this._fs = tryRequire('fs');
    this._proc = (typeof process !== 'undefined') ? process : {
      stdout: { write: function() {} },
      stderr: { write: function() {} },
      exit: function() {},
      hrtime: { bigint: function() { return 0n; } }
    };

    // File descriptor table.
    //   0,1,2  -> stdin/stdout/stderr (special, never closed)
    //   >=3    -> preopen dirs first, then user-opened files
    this._fds = Object.create(null);
    this._fds[0] = { type: 'stdin' };
    this._fds[1] = { type: 'stdout' };
    this._fds[2] = { type: 'stderr' };

    var nextFd = 3;
    var preopens = this.preopens;
    var preopenPaths = Object.keys(preopens);
    for (var i = 0; i < preopenPaths.length; i++) {
      var wasmPath = preopenPaths[i];
      var hostPath = preopens[wasmPath];
      this._fds[nextFd++] = {
        type: 'dir',
        wasmPath: wasmPath,
        hostPath: hostPath,
        offset: 0n
      };
    }
    this._nextFd = nextFd;

    this._instance = null;
    this._memory = null;
    this._exitCode = 0;
  }

  WASI.prototype._mem = function() {
    if (!this._instance) throw new Error('WASI: instance not bound');
    if (!this._memory) {
      var m = this._instance.exports.memory;
      if (!m) throw new Error('WASI: instance has no exported memory');
      this._memory = m;
    }
    return new DataView(this._memory.buffer);
  };

  WASI.prototype._memBytes = function() {
    return new Uint8Array(this._memory.buffer);
  };

  WASI.prototype._writeUint32 = function(view, off, val) {
    view.setUint32(off, val >>> 0, true);
  };

  WASI.prototype._writeUint64 = function(view, off, val) {
    view.setBigUint64(off, BigInt(val), true);
  };

  WASI.prototype._writeBytes = function(off, bytes) {
    var mem = this._memBytes();
    mem.set(bytes, off);
  };

  WASI.prototype._readString = function(off, len) {
    var mem = this._memBytes();
    return new TextDecoder('utf-8').decode(mem.subarray(off, off + len));
  };

  // Resolve a path under a preopen, preventing escape with parent traversal.
  WASI.prototype._resolvePath = function(fd, relPath) {
    var entry = this._fds[fd];
    if (!entry || entry.type !== 'dir') return null;
    var path = tryRequire('path');
    if (!path) return null;
    var resolved = path.normalize(path.join(entry.hostPath, relPath));
    var base = path.normalize(entry.hostPath);
    if (!resolved.startsWith(base)) return null;
    return resolved;
  };

  WASI.prototype.getImportObject = function() {
    return { wasi_snapshot_preview1: this.wasiImport() };
  };

  WASI.prototype.wasiImport = function() {
    var self = this;
    return {
      args_get: function(argvOff, argvBufOff) {
        var view = self._mem();
        var enc = new TextEncoder();
        var ptr = argvBufOff;
        for (var i = 0; i < self.args.length; i++) {
          self._writeUint32(view, argvOff + i * 4, ptr);
          var bytes = enc.encode(self.args[i] + '\0');
          self._writeBytes(ptr, bytes);
          ptr += bytes.length;
        }
        return WASI_ESUCCESS;
      },

      args_sizes_get: function(countOff, bufSizeOff) {
        var view = self._mem();
        var enc = new TextEncoder();
        var total = 0;
        for (var i = 0; i < self.args.length; i++)
          total += enc.encode(self.args[i]).length + 1;
        self._writeUint32(view, countOff, self.args.length);
        self._writeUint32(view, bufSizeOff, total);
        return WASI_ESUCCESS;
      },

      environ_get: function(envOff, envBufOff) {
        var view = self._mem();
        var enc = new TextEncoder();
        var keys = Object.keys(self.env);
        var ptr = envBufOff;
        for (var i = 0; i < keys.length; i++) {
          self._writeUint32(view, envOff + i * 4, ptr);
          var s = keys[i] + '=' + self.env[keys[i]] + '\0';
          var bytes = enc.encode(s);
          self._writeBytes(ptr, bytes);
          ptr += bytes.length;
        }
        return WASI_ESUCCESS;
      },

      environ_sizes_get: function(countOff, bufSizeOff) {
        var view = self._mem();
        var enc = new TextEncoder();
        var keys = Object.keys(self.env);
        var total = 0;
        for (var i = 0; i < keys.length; i++)
          total += enc.encode(keys[i] + '=' + self.env[keys[i]]).length + 1;
        self._writeUint32(view, countOff, keys.length);
        self._writeUint32(view, bufSizeOff, total);
        return WASI_ESUCCESS;
      },

      clock_time_get: function(clockId, _precision, timeOff) {
        var view = self._mem();
        var nanos;
        if (clockId === WASI_CLOCK_REALTIME) {
          nanos = BigInt(Date.now()) * 1000000n;
        } else if (clockId === WASI_CLOCK_MONOTONIC) {
          if (self._proc.hrtime && self._proc.hrtime.bigint)
            nanos = self._proc.hrtime.bigint();
          else
            nanos = BigInt(Math.floor(performance.now() * 1e6));
        } else {
          return WASI_EINVAL;
        }
        self._writeUint64(view, timeOff, nanos);
        return WASI_ESUCCESS;
      },

      random_get: function(bufOff, bufLen) {
        var mem = self._memBytes();
        if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
          var chunk = 65536;
          for (var off = 0; off < bufLen; off += chunk) {
            var n = Math.min(chunk, bufLen - off);
            var tmp = new Uint8Array(n);
            crypto.getRandomValues(tmp);
            mem.set(tmp, bufOff + off);
          }
        } else {
          for (var i = 0; i < bufLen; i++)
            mem[bufOff + i] = (Math.random() * 256) | 0;
        }
        return WASI_ESUCCESS;
      },

      proc_exit: function(code) {
        self._exitCode = code;
        if (self.returnOnExit) {
          throw new WasiExitError(code);
        } else {
          self._proc.exit(code);
        }
      },

      fd_close: function(fd) {
        var entry = self._fds[fd];
        if (!entry) return WASI_EBADF;
        if (entry.type === 'file' && entry.hostFd != null && self._fs) {
          try { self._fs.closeSync(entry.hostFd); } catch (_) {}
        }
        delete self._fds[fd];
        return WASI_ESUCCESS;
      },

      fd_fdstat_get: function(fd, statOff) {
        var view = self._mem();
        var entry = self._fds[fd];
        if (!entry) return WASI_EBADF;
        var ftype = WASI_FILETYPE_UNKNOWN;
        if (entry.type === 'stdin' || entry.type === 'stdout' || entry.type === 'stderr')
          ftype = WASI_FILETYPE_CHARACTER_DEVICE;
        else if (entry.type === 'dir') ftype = WASI_FILETYPE_DIRECTORY;
        else if (entry.type === 'file') ftype = WASI_FILETYPE_REGULAR_FILE;
        view.setUint8(statOff, ftype);
        view.setUint16(statOff + 2, 0, true);
        view.setBigUint64(statOff + 8, WASI_RIGHTS_ALL, true);
        view.setBigUint64(statOff + 16, WASI_RIGHTS_ALL, true);
        return WASI_ESUCCESS;
      },

      fd_fdstat_set_flags: function(_fd, _flags) {
        return WASI_ESUCCESS;
      },

      fd_prestat_get: function(fd, prestatOff) {
        var view = self._mem();
        var entry = self._fds[fd];
        if (!entry || entry.type !== 'dir') return WASI_EBADF;
        view.setUint8(prestatOff, WASI_PREOPENTYPE_DIR);
        view.setUint32(prestatOff + 4, new TextEncoder().encode(entry.wasmPath).length, true);
        return WASI_ESUCCESS;
      },

      fd_prestat_dir_name: function(fd, pathOff, pathLen) {
        var entry = self._fds[fd];
        if (!entry || entry.type !== 'dir') return WASI_EBADF;
        var bytes = new TextEncoder().encode(entry.wasmPath);
        if (bytes.length > pathLen) return WASI_EINVAL;
        self._writeBytes(pathOff, bytes);
        return WASI_ESUCCESS;
      },

      fd_read: function(fd, iovsOff, iovsLen, nreadOff) {
        var view = self._mem();
        var mem = self._memBytes();
        var entry = self._fds[fd];
        if (!entry) return WASI_EBADF;
        var total = 0;
        for (var i = 0; i < iovsLen; i++) {
          var buf = view.getUint32(iovsOff + i * 8, true);
          var len = view.getUint32(iovsOff + i * 8 + 4, true);
          if (len === 0) continue;
          if (entry.type === 'file' && self._fs && entry.hostFd != null) {
            try {
              var tmp = Buffer.alloc(len);
              var n = self._fs.readSync(entry.hostFd, tmp, 0, len, null);
              if (n > 0) mem.set(tmp.subarray(0, n), buf);
              total += n;
              if (n < len) break;
            } catch (e) {
              return mapNodeErrno(e);
            }
          } else {
            // stdin reads return 0 (EOF) — we don't yet pump stdin
            // synchronously into wasi.
            break;
          }
        }
        self._writeUint32(view, nreadOff, total);
        return WASI_ESUCCESS;
      },

      fd_write: function(fd, iovsOff, iovsLen, nwrittenOff) {
        var view = self._mem();
        var mem = self._memBytes();
        var entry = self._fds[fd];
        if (!entry) return WASI_EBADF;
        var total = 0;
        for (var i = 0; i < iovsLen; i++) {
          var buf = view.getUint32(iovsOff + i * 8, true);
          var len = view.getUint32(iovsOff + i * 8 + 4, true);
          if (len === 0) continue;
          var slice = mem.subarray(buf, buf + len);
          if (entry.type === 'stdout') {
            self._proc.stdout.write(slice);
            total += len;
          } else if (entry.type === 'stderr') {
            self._proc.stderr.write(slice);
            total += len;
          } else if (entry.type === 'file' && self._fs && entry.hostFd != null) {
            try {
              var n = self._fs.writeSync(entry.hostFd, slice, 0, len);
              total += n;
            } catch (e) {
              return mapNodeErrno(e);
            }
          } else {
            return WASI_EBADF;
          }
        }
        self._writeUint32(view, nwrittenOff, total);
        return WASI_ESUCCESS;
      },

      fd_seek: function(fd, offset, whence, newOffsetOff) {
        var view = self._mem();
        var entry = self._fds[fd];
        if (!entry || entry.type !== 'file' || entry.hostFd == null || !self._fs)
          return WASI_EBADF;
        // No portable lseek in dun:fs yet; track offset locally for
        // wasi-libc which only uses fd_seek to query the current position.
        entry.offset = entry.offset || 0n;
        var off = BigInt(offset);
        if (whence === WASI_WHENCE_SET) entry.offset = off;
        else if (whence === WASI_WHENCE_CUR) entry.offset = entry.offset + off;
        else if (whence === WASI_WHENCE_END) entry.offset = entry.size || 0n;
        else return WASI_EINVAL;
        view.setBigUint64(newOffsetOff, entry.offset, true);
        return WASI_ESUCCESS;
      },

      fd_tell: function(fd, offsetOff) {
        var view = self._mem();
        var entry = self._fds[fd];
        if (!entry || entry.type !== 'file') return WASI_EBADF;
        view.setBigUint64(offsetOff, entry.offset || 0n, true);
        return WASI_ESUCCESS;
      },

      path_open: function(dirfd, _dirflags, pathOff, pathLen,
                          oflags, _fsRights, _fsRightsInheriting, fdflags, fdOff) {
        if (!self._fs) return WASI_ENOSYS;
        var view = self._mem();
        var relPath = self._readString(pathOff, pathLen);
        var hostPath = self._resolvePath(dirfd, relPath);
        if (hostPath == null) return WASI_EBADF;

        var flag = 'r';
        var creat = (oflags & WASI_O_CREAT) !== 0;
        var trunc = (oflags & WASI_O_TRUNC) !== 0;
        var excl = (oflags & WASI_O_EXCL) !== 0;
        var append = (fdflags & WASI_FDFLAG_APPEND) !== 0;

        if (creat && trunc) flag = excl ? 'wx' : 'w';
        else if (creat) flag = excl ? 'ax' : 'a';
        else if (trunc) flag = 'r+';
        else if (append) flag = 'a';

        try {
          var hostFd = self._fs.openSync(hostPath, flag);
          var st;
          try { st = self._fs.fstatSync(hostFd); } catch (_) { st = null; }
          var entry = {
            type: 'file',
            hostFd: hostFd,
            hostPath: hostPath,
            offset: 0n,
            size: st ? BigInt(st.size) : 0n
          };
          var fd = self._nextFd++;
          self._fds[fd] = entry;
          self._writeUint32(view, fdOff, fd);
          return WASI_ESUCCESS;
        } catch (e) {
          return mapNodeErrno(e);
        }
      },

      // Stubs for less common syscalls — return ENOSYS so libc
      // can fall back to error handling.
      fd_advise:        function() { return WASI_ESUCCESS; },
      fd_allocate:      function() { return WASI_ENOSYS; },
      fd_datasync:      function() { return WASI_ESUCCESS; },
      fd_filestat_get:  function(fd, statOff) {
        var view = self._mem();
        var entry = self._fds[fd];
        if (!entry) return WASI_EBADF;
        // Zero-fill 64-byte filestat
        for (var i = 0; i < 64; i++) view.setUint8(statOff + i, 0);
        var ftype = WASI_FILETYPE_UNKNOWN;
        if (entry.type === 'dir') ftype = WASI_FILETYPE_DIRECTORY;
        else if (entry.type === 'file') ftype = WASI_FILETYPE_REGULAR_FILE;
        else ftype = WASI_FILETYPE_CHARACTER_DEVICE;
        view.setUint8(statOff + 16, ftype);
        view.setBigUint64(statOff + 32, entry.size || 0n, true);
        return WASI_ESUCCESS;
      },
      fd_filestat_set_size: function() { return WASI_ENOSYS; },
      fd_filestat_set_times: function() { return WASI_ESUCCESS; },
      fd_pread:        function() { return WASI_ENOSYS; },
      fd_pwrite:       function() { return WASI_ENOSYS; },
      fd_readdir:      function() { return WASI_ENOSYS; },
      fd_renumber:     function() { return WASI_ENOSYS; },
      fd_sync:         function() { return WASI_ESUCCESS; },
      path_create_directory: function(dirfd, pathOff, pathLen) {
        if (!self._fs) return WASI_ENOSYS;
        var hostPath = self._resolvePath(dirfd, self._readString(pathOff, pathLen));
        if (hostPath == null) return WASI_EBADF;
        try { self._fs.mkdirSync(hostPath); return WASI_ESUCCESS; }
        catch (e) { return mapNodeErrno(e); }
      },
      path_filestat_get: function(dirfd, _flags, pathOff, pathLen, statOff) {
        if (!self._fs) return WASI_ENOSYS;
        var view = self._mem();
        var hostPath = self._resolvePath(dirfd, self._readString(pathOff, pathLen));
        if (hostPath == null) return WASI_EBADF;
        try {
          var st = self._fs.statSync(hostPath);
          for (var i = 0; i < 64; i++) view.setUint8(statOff + i, 0);
          view.setUint8(statOff + 16, st.isDirectory() ? WASI_FILETYPE_DIRECTORY : WASI_FILETYPE_REGULAR_FILE);
          view.setBigUint64(statOff + 32, BigInt(st.size), true);
          return WASI_ESUCCESS;
        } catch (e) { return mapNodeErrno(e); }
      },
      path_filestat_set_times: function() { return WASI_ESUCCESS; },
      path_link:       function() { return WASI_ENOSYS; },
      path_readlink:   function() { return WASI_ENOSYS; },
      path_remove_directory: function(dirfd, pathOff, pathLen) {
        if (!self._fs) return WASI_ENOSYS;
        var hostPath = self._resolvePath(dirfd, self._readString(pathOff, pathLen));
        if (hostPath == null) return WASI_EBADF;
        try { self._fs.rmdirSync(hostPath); return WASI_ESUCCESS; }
        catch (e) { return mapNodeErrno(e); }
      },
      path_rename:     function() { return WASI_ENOSYS; },
      path_symlink:    function() { return WASI_ENOSYS; },
      path_unlink_file: function(dirfd, pathOff, pathLen) {
        if (!self._fs) return WASI_ENOSYS;
        var hostPath = self._resolvePath(dirfd, self._readString(pathOff, pathLen));
        if (hostPath == null) return WASI_EBADF;
        try { self._fs.unlinkSync(hostPath); return WASI_ESUCCESS; }
        catch (e) { return mapNodeErrno(e); }
      },
      poll_oneoff:     function() { return WASI_ENOSYS; },
      sched_yield:     function() { return WASI_ESUCCESS; },
      sock_recv:       function() { return WASI_ENOSYS; },
      sock_send:       function() { return WASI_ENOSYS; },
      sock_shutdown:   function() { return WASI_ENOSYS; }
    };
  };

  function WasiExitError(code) {
    this.name = 'WasiExitError';
    this.code = code;
    this.message = 'WASI exit (' + code + ')';
  }
  WasiExitError.prototype = Object.create(Error.prototype);
  WasiExitError.prototype.constructor = WasiExitError;

  WASI.prototype.start = function(instance) {
    this._instance = instance;
    var startFn = instance.exports._start;
    if (typeof startFn !== 'function')
      throw new Error('WASI start: instance has no _start export');
    try {
      startFn();
    } catch (e) {
      if (e instanceof WasiExitError) return e.code;
      throw e;
    }
    return this._exitCode;
  };

  WASI.prototype.initialize = function(instance) {
    this._instance = instance;
    var initFn = instance.exports._initialize;
    if (typeof initFn === 'function') initFn();
  };

  var mod = { WASI: WASI };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_wasi__ = mod;
  }
})();`;
}
