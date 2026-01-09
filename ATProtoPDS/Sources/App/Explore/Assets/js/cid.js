const CODECS = {
    0x55: 'raw',
    0x70: 'dag-pb',
    0x71: 'dag-cbor',
    0x72: 'dag-json',
    0x129: 'dag-json'
};

const HASH_ALGS = {
    0x11: 'SHA-1',
    0x12: 'SHA-256',
    0x13: 'SHA-512',
    0xb220: 'Blake2b-256',
    0xb240: 'Blake2b-512'
};

export class CIDDecoder {
    static decode(cid) {
        if (!cid || cid.length < 2) {
            return { error: 'Invalid CID: too short' };
        }
        
        const result = {
            input: cid,
            version: null,
            multibase: null,
            codec: null,
            codecName: null,
            multihash: {
                algorithm: null,
                algorithmCode: null,
                size: null,
                digest: null
            },
            byteLength: null,
            rawBytes: null,
            rawBytesHex: null
        };
        
        const prefix = cid[0];
        const encoded = cid.slice(1);
        result.multibase = prefix;
        
        const bytes = this.base32Decode(encoded);
        if (!bytes || bytes.length === 0) {
            return { error: 'Invalid CID: failed to decode base32' };
        }
        
        result.rawBytes = bytes;
        result.byteLength = bytes.length;
        result.rawBytesHex = Array.from(bytes)
            .map(b => b.toString(16).padStart(2, '0'))
            .join(' ');
        
        let offset = 0;
        let version = 0;
        while (offset < bytes.length && (bytes[offset] & 0x80)) {
            version = (version << 7) | (bytes[offset] & 0x7f);
            offset++;
            if (offset >= bytes.length) break;
        }
        version = (version << 7) | (bytes[offset] & 0x7f);
        offset++;
        result.version = version;
        
        if (version === 0) {
            result.codec = 'N/A';
            result.codecName = 'CIDv0 (base58)';
            result.multihash.algorithm = 'N/A';
            result.multihash.algorithmCode = 'N/A';
            result.multihash.size = 'N/A';
            result.multihash.digest = 'N/A';
        } else if (version === 1) {
            let codec = 0;
            let codecOffset = offset;
            while (offset < bytes.length && (bytes[offset] & 0x80)) {
                codec = (codec << 7) | (bytes[offset] & 0x7f);
                offset++;
                if (offset >= bytes.length) break;
            }
            codec = (codec << 7) | (bytes[offset] & 0x7f);
            offset++;
            result.codec = '0x' + codec.toString(16);
            result.codecName = CODECS[codec] || `unknown (0x${codec.toString(16)})`;
            
            let hashAlg = 0;
            while (offset < bytes.length && (bytes[offset] & 0x80)) {
                hashAlg = (hashAlg << 7) | (bytes[offset] & 0x7f);
                offset++;
                if (offset >= bytes.length) break;
            }
            hashAlg = (hashAlg << 7) | (bytes[offset] & 0x7f);
            offset++;
            result.multihash.algorithmCode = '0x' + hashAlg.toString(16);
            result.multihash.algorithm = HASH_ALGS[hashAlg] || `unknown (0x${hashAlg.toString(16)})`;
            
            if (offset < bytes.length) {
                result.multihash.size = bytes[offset];
                offset++;
                
                const digestBytes = bytes.slice(offset);
                result.multihash.digest = Array.from(digestBytes)
                    .map(b => b.toString(16).padStart(2, '0'))
                    .join('');
            } else {
                result.multihash.size = 0;
                result.multihash.digest = '';
            }
        } else {
            return { error: `Unknown CID version: ${version}` };
        }
        
        return result;
    }
    
    static base32Decode(str) {
        const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
        const result = [];
        let buffer = 0;
        let bits = 0;
        
        for (let i = 0; i < str.length; i++) {
            const c = str[i].toLowerCase();
            let val = -1;
            for (let j = 0; j < alphabet.length; j++) {
                if (alphabet[j] === c) {
                    val = j;
                    break;
                }
            }
            if (val === -1) continue;
            
            buffer = (buffer << 5) | val;
            bits += 5;
            
            while (bits >= 8) {
                bits -= 8;
                result.push((buffer >> bits) & 0xFF);
            }
        }
        
        return result;
    }
    
    static render(decoded) {
        if (decoded.error) {
            return `<p class="error">${decoded.error}</p>`;
        }
        
        return `
            <table class="cid-table">
                <tr>
                    <td class="label">Version</td>
                    <td>${decoded.version}</td>
                </tr>
                <tr>
                    <td class="label">Multibase</td>
                    <td>${decoded.multibase}</td>
                </tr>
                <tr>
                    <td class="label">Codec</td>
                    <td>${decoded.codec} (${decoded.codecName})</td>
                </tr>
                <tr>
                    <td class="label">Hash Algorithm</td>
                    <td>${decoded.multihash.algorithm} (${decoded.multihash.algorithmCode})</td>
                </tr>
                <tr>
                    <td class="label">Hash Size</td>
                    <td>${decoded.multihash.size} bytes</td>
                </tr>
                <tr>
                    <td class="label">Digest</td>
                    <td><code>${decoded.multihash.digest}</code></td>
                </tr>
                <tr>
                    <td class="label">Byte Length</td>
                    <td>${decoded.byteLength} bytes</td>
                </tr>
            </table>
            <div class="raw-bytes">
                <h4>Raw Bytes</h4>
                <pre>${decoded.rawBytesHex}</pre>
            </div>
        `;
    }
}
