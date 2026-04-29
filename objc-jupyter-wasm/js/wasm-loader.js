// wasm-loader.js
// WebAssembly loading utilities for Objective-C kernel

export const WasmLoader = {
    memory: null,
    instances: new Map(),

    /**
     * Load a WASM module from URL
     */
    async load(path, imports) {
        const response = await fetch(path);
        const buffer = await response.arrayBuffer();
        
        const module = await WebAssembly.compile(buffer);
        const instance = await WebAssembly.instantiate(module, imports);
        
        this.instances.set(path, instance);
        
        if (!this.memory) {
            this.memory = instance.exports.memory || new WebAssembly.Memory({ initial: 256 });
        }
        
        return instance;
    },

    /**
     * Get the memory buffer from WASM instance
     */
    getMemoryBuffer() {
        return this.memory ? this.memory.buffer : new ArrayBuffer(0);
    },

    /**
     * Read a null-terminated string from WASM memory
     */
    readString(ptr) {
        if (!ptr || !this.memory) return '';
        
        const buffer = new Uint8Array(this.getMemoryBuffer());
        let str = '';
        let i = ptr;
        
        while (i < buffer.length && buffer[i] !== 0) {
            str += String.fromCharCode(buffer[i++]);
        }
        
        return str;
    },

    /**
     * Write a string to WASM memory
     */
    writeString(str) {
        if (!this.memory) return 0;
        
        const buffer = new Uint8Array(this.getMemoryBuffer());
        const ptr = new Uint32Array(this.getMemoryBuffer())[0]; // Use first 4 bytes as allocation pointer
        
        for (let i = 0; i < str.length; i++) {
            buffer[ptr + i] = str.charCodeAt(i);
        }
        buffer[ptr + str.length] = 0; // null terminator
        
        return ptr;
    }
};
