 #!/usr/bin/env python3
"""Add test files to the Xcode project."""

import re
import sys

PROJECT_FILE = "ATProtoPDS.xcodeproj/project.pbxproj"

# New test files to add
TEST_FILES = [
    "tests/Database/ActorStore/ActorStoreTests.m",
    "tests/Database/Pool/DatabasePoolTests.m", 
    "tests/Database/Service/ServiceDatabasesTests.m",
    "tests/Database/PDSControllerTests.m",
]

def md5_hash(s):
    """Generate a short hash for file ID."""
    import hashlib
    return hashlib.md5(s.encode()).hexdigest()[:24]

def add_files_to_project():
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Find insertion points for Tests sections
    tests_file_ref_pattern = r'(// Tests\r?\n\t\tATPROTO_HTTP_SERVER_TEST = \{isa = PBXFileReference;.*?;\r?\n\t\tATPROTO_BLOB_STORAGE_TESTS = \{isa = PBXFileReference;.*?;\r?\n)'
    tests_build_file_pattern = r'(// Tests\r?\n\t\tATPROTO_HTTP_SERVER_TEST = \{isa = PBXBuildFile;.*?;\r?\n\t\tATPROTO_BLOB_STORAGE_TESTS = \{isa = PBXBuildFile;.*?;\r?\n)'
    tests_group_pattern = r'(ATPROTO_TESTS_GROUP = \{\r?\n\t\tisa = PBXGroup;\r?\n\t\tchildren = \(\r?\n\t\t\tATPROTO_HTTP_SERVER_TEST,\r?\n\t\t\tATPROTO_BLOB_STORAGE_TESTS,\r?\n\t\t\);\r?\n)'
    
    new_file_refs = []
    new_build_files = []
    new_group_refs = []
    
    for file_path in TEST_FILES:
        file_id = md5_hash(file_path)
        
        # Check if already exists
        if file_path in content:
            print(f"File already exists: {file_path}")
            continue
        
        # Create file reference entry
        file_ref = f'\t\tATPROTO_{file_id} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = {file_path}; sourceTree = "<group>"; }};'
        new_file_refs.append(file_ref)
        
        # Create build file entry
        build_file = f'\t\tATPROTO_{file_id} = {{isa = PBXBuildFile; fileRef = ATPROTO_{file_id}; }};'
        new_build_files.append(build_file)
        
        # Create group reference
        group_ref = f'\t\t\tATPROTO_{file_id},'
        new_group_refs.append(group_ref)
        
        print(f"Added: {file_path}")
    
    # Insert file references after ATPROTO_BLOB_STORAGE_TESTS in Tests section
    if new_file_refs:
        new_file_refs_str = '\n'.join(new_file_refs) + '\n'
        match = re.search(tests_file_ref_pattern, content)
        if match:
            insert_pos = match.end()
            content = content[:insert_pos] + new_file_refs_str + content[insert_pos:]
    
    # Insert build files after ATPROTO_BLOB_STORAGE_TESTS in Tests section
    if new_build_files:
        new_build_files_str = '\n'.join(new_build_files) + '\n'
        match = re.search(tests_build_file_pattern, content)
        if match:
            insert_pos = match.end()
            content = content[:insert_pos] + new_build_files_str + content[insert_pos:]
    
    # Insert group references after ATPROTO_BLOB_STORAGE_TESTS in ATPROTO_TESTS_GROUP
    if new_group_refs:
        new_group_refs_str = '\n'.join(new_group_refs) + '\n'
        match = re.search(tests_group_pattern, content)
        if match:
            insert_pos = match.end()
            content = content[:insert_pos] + new_group_refs_str + content[insert_pos:]
    
    # Write back
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)
    
    print(f"\nAdded {len(new_file_refs)} file references and {len(new_build_files)} build files")

if __name__ == "__main__":
    add_files_to_project()
