import hashlib
import cbor2

# Target digest
target_digest = "29e2e42d820d8d5e77f6ec8b4ae746b1a72d86cfcbb20700b35ed6c1e982791d"

val_digest = bytes.fromhex("9d156bc3f3a520066252c708a9361fd3d089223842500e3713d404fdccb33cef")
val_cid = b"\x01\x71\x12\x20" + val_digest

k_suffix = b"com.example.record/3jqfcqzm3fo2j"

def tag_42_encoder(encoder, value):
    encoder.encode(cbor2.CBORTag(42, value))

def check(node):
    # Sort keys for DAG-CBOR
    def sort_dict(d):
        if isinstance(d, dict):
            return {k: sort_dict(v) for k, v in sorted(d.items())}
        if isinstance(d, list):
            return [sort_dict(x) for x in d]
        return d

    node_sorted = sort_dict(node)
    encoded = cbor2.dumps(node_sorted, default=tag_42_encoder)
    digest = hashlib.sha256(encoded).hexdigest()
    if digest == target_digest:
        print(f"FOUND IT! Node: {node}")
        print(f"CBOR: {encoded.hex()}")
        return True
    return False

# Try combinations
for l_present in [True, False]:
    for l_val in [None, val_cid]:
        for t_present in [True, False]:
            for t_val in [None, val_cid]:
                entry = {"k": k_suffix, "p": 0, "v": cbor2.CBORTag(42, val_cid)}
                if t_present:
                    entry["t"] = cbor2.CBORTag(42, t_val) if t_val else None
                
                node = {"e": [entry]}
                if l_present:
                    node["l"] = cbor2.CBORTag(42, l_val) if l_val else None
                
                if check(node):
                    exit()

print("Not found with simple combinations.")
