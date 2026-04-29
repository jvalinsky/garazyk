// kernel.js
// JupyterLite kernel entry point for Objective-C

importScripts('./wasm-loader.js');

let kernelWasm = null;
let executionCount = 0;

// Initialize WASM kernel
async function initKernel() {
    try {
        const response = await fetch('./kernel/kernel.wasm');
        const buffer = await response.arrayBuffer();
        const module = await WebAssembly.compile(buffer);
        
        kernelWasm = await WebAssembly.instantiate(module, createWasiImports());
        
        console.log('Objective-C kernel initialized');
    } catch (error) {
        console.error('Failed to initialize kernel:', error);
    }
}

// Create WASI imports
function createWasiImports() {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    let memory = null;

    return {
        wasi_snapshot_preview1: {
            fd_write: (fd, iovs, iovs_len, nwritten) => {
                // Capture output
                if (fd === 1 || fd === 2) {
                    const stdout = decoder.decode(
                        new Uint8Array(memory.buffer, iovs, iovs_len)
                    );
                    postMessage({
                        type: 'stream',
                        name: fd === 1 ? 'stdout' : 'stderr',
                        text: stdout
                    });
                }
                return 0;
            },
            proc_exit: (code) => {
                console.log(`Kernel exit: ${code}`);
            }
        },
        env: {
            objc_log: (ptr) => {
                const str = readString(ptr);
                postMessage({
                    type: 'stream',
                    name: 'stderr',
                    text: `[ObjC] ${str}\n`
                });
            }
        },
        memory: memory
    };
}

// Read string from WASM memory
function readString(ptr) {
    if (!ptr || !memory) return '';
    const buffer = new Uint8Array(memory.buffer);
    let str = '';
    let i = ptr;
    while (i < buffer.length && buffer[i] !== 0) {
        str += String.fromCharCode(buffer[i++]);
    }
    return str;
}

// Handle messages from Jupyter frontend
onmessage = async (e) => {
    const { type, code, cellId } = e.data;

    if (type === 'execute_request') {
        if (!kernelWasm) {
            await initKernel();
        }

        executionCount++;

        try {
            // Call WASM execute
            const execute = kernelWasm.exports.execute || kernelWasm.exports.wasm_kernel_execute;
            if (execute) {
                const resultPtr = execute(code, cellId || '0');
                const result = readString(resultPtr);

                postMessage({
                    type: 'execute_result',
                    status: 'ok',
                    execution_count: executionCount,
                    data: {
                        'text/plain': result || '[Executed]'
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
};

// Initialize on load
initKernel();
