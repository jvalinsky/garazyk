## Common Pitfalls and Solutions

### Error Handling Mistakes

**❌ Problem: Silent failures**
```bash
# Bad: Commands can fail silently
cp source dest
rm temp_file
```

**✅ Solution: Check exit codes**
```bash
if ! cp source dest; then
    error_exit "Failed to copy file"
fi

rm temp_file  # Safe because script exits on cp failure
```

### Variable Scoping Issues

**❌ Problem: Global variables in functions**
```bash
process_files() {
    for file in *; do
        count=$((count + 1))  # Modifies global count
    done
}
```

**✅ Solution: Use local variables**
```bash
process_files() {
    local file_count=0
    for file in *; do
        ((file_count++))
    done
    echo "$file_count"
}
```

### Path Handling Errors

**❌ Problem: Unsafe path handling**
```bash
backup_dir="$1"
cd "$backup_dir"  # Could be dangerous
```

**✅ Solution: Validate paths**
```bash
validate_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        error_exit "Not a directory: $dir"
    fi
    
    if [[ ! -w "$dir" ]]; then
        error_exit "Cannot write to directory: $dir"
    fi
}

backup_dir="$1"
validate_directory "$backup_dir"
cd "$backup_dir"
```

### Performance Anti-patterns

**❌ Problem: Inefficient loops**
```bash
for file in $(find . -name "*.txt"); do
    process_file "$file"  # Creates subshell for each file
done
```

**✅ Solution: Use process substitution**
```bash
while IFS= read -r -d '' file; do
    process_file "$file"
done < <(find . -name "*.txt" -print0)
```
