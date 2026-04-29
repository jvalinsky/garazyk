// wasi-harness.js
// WASI implementation following c2wasm pattern

export function createWasiHarness() {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    
    // Virtual file system (Emscripten-style)
    const fs = {
        files: new Map(),
        writeFile: function(path, content) {
            if (typeof content === 'string') {
                this.files.set(path, encoder.encode(content));
            } else {
                this.files.set(path, content);
            }
        },
        readFile: function(path) {
            return this.files.get(path) || null;
        }
    };

    // Initialize with some default files
    fs.writeFile('/tmp/', new Uint8Array(0)); // directory marker

    return {
        wasi_snapshot_preview1: {
            // File descriptor operations
            fd_write: function(fd, iovs, iovs_len, nwritten) {
                // Simplified: assume fd 1 = stdout, fd 2 = stderr
                let totalWritten = 0;
                
                // In a real implementation, read from memory using iovs
                // For now, just return success
                if (nwritten !== 0) {
                    new DataView(this.memory.buffer).setUint32(nwritten, totalWritten, true);
                }
                return 0;
            },

            fd_read: function(fd, iovs, iovs_len, nread) {
                return 0;
            },

            fd_close: function(fd) {
                return 0;
            },

            fd_seek: function(fd, offset, whence, newOffset) {
                return 0;
            },

            path_open: function(pathPtr, pathLen, dirfd, lookupFlags, openFlags, fsRightsBase, fsRightsInheriting, fdFlags, fdOut) {
                return 0;
            },

            proc_exit: function(code) {
                console.log(`WASM process exited with code: ${code}`);
            }
        },

        // Memory will be set by WASM instance
        memory: null,

        // FS accessor
        fs: fs
    };
}
