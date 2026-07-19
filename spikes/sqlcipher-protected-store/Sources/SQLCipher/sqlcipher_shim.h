// sqlcipher's pkg-config Cflags must make sqlite3.h available.  This shim is
// intentionally not allowed to include the macOS SDK's libsqlite3 fallback.
#include <sqlite3.h>
