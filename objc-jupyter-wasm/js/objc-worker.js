// objc-worker.js
// Web Worker entry point for Objective-C Jupyter kernel

importScripts('./wasm-loader.js');

let kernelInstance = null;
let wasiImports = null;

// Initialize WASI imports
function createWasiImports() {
    return {
        wasi_snapshot_preview1: {
            fd_write: (fd, iovs, iovs_len, nwritten) => {
                // Implementation for capturing output
                return 0;
            },
            proc_exit: (code) => {
                console.log(`WASM exit: ${code}`);
            }
        },
        env: {
            objc_log: (ptr) => {
                const str = WasmLoader.readString(ptr);
                postMessage({ type: 'stream', name: 'stderr', text: `[ObjC] ${str}\n` });
            }
        }
    };
}

// Handle messages from main thread
onmessage = async (e) => {
    const { type, code, cellId, cursorPos, detailLevel } = e.data;

    if (type === 'execute_request') {
        try {
            if (!kernelInstance) {
                // Load kernel WASM
                const result = await fetch('./kernel.wasm');
                const buffer = await result.arrayBuffer();
                const module = await WebAssembly.compile(buffer);
                kernelInstance = await WebAssembly.instantiate(module, createWasiImports());
            }

            // Call execute
            const executeFn = kernelInstance.exports.execute || kernelInstance.exports.wasm_kernel_execute;
            if (executeFn) {
                const result = executeFn(code, cellId);
                postMessage({
                    type: 'execute_result',
                    status: 'ok',
                    execution_count: e.data.count || 1,
                    data: {
                        'text/plain': WasmLoader.readString(result) || 'Executed'
                    }
                });
            } else {
                postMessage({
                    type: 'execute_result',
                    status: 'error',
                    ename: 'NotImplemented',
                    evalue: 'Execute function not found in WASM module'
                });
            }
        } catch (error) {
            postMessage({
                type: 'execute_result',
                status: 'error',
                ename: 'ExecutionError',
                evalue: error.message,
                traceback: []
            });
        }
    }

    if (type === 'complete_request') {
        // Basic completion
        const partial = code.substring(0, cursorPos).split(/[\s;{}]+/).pop() || '';
        const keywords = ['@interface', '@implementation', '@end', '@property', 
            'nil', 'NSString', 'NSArray', 'NSDictionary', 'alloc', 'init'];
        const matches = keywords.filter(k => k.startsWith(partial));
        
        postMessage({
            type: 'complete_reply',
            status: 'ok',
            matches,
            cursor_start: cursorPos - partial.length,
            cursor_end: cursorPos
        });
    }
};
