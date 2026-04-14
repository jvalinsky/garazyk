#!/bin/bash
# Script to add test files to the Xcode project

PROJECT_FILE="ATProtoPDS.xcodeproj/project.pbxproj"

# New test files to add
declare -a TEST_FILES=(
    "tests/Database/ActorStore/ActorStoreTests.m"
    "tests/Database/Pool/DatabasePoolTests.m"
    "tests/Database/Service/ServiceDatabasesTests.m"
    "tests/Database/PDSControllerTests.m"
)

# Function to add a file reference
add_file_reference() {
    local file_path=$1
    local file_id=$(echo "$file_path" | md5 | cut -c1-24)
    local path_escaped=$(echo "$file_path" | sed 's/\//\\\//g')
    
    # Check if already exists
    if grep -q "$file_path" "$PROJECT_FILE"; then
        echo "File already exists: $file_path"
        return
    fi
    
    # Find the last PBXFileReference entry and insert after it
    local last_ref_line=$(grep -n "/* End PBXFileReference section */" "$PROJECT_FILE" | cut -d: -f1)
    
    # Create the new entry
    local new_entry="\t\tATPROTO_${file_id} = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = ${path_escaped}; sourceTree = \"<group>\"; };"
    
    # Insert the new entry before the end section
    sed -i '' "${last_ref_line}i\\
${new_entry}" "$PROJECT_FILE"
    
    echo "Added file reference: $file_path"
}

# Function to add a build file
add_build_file() {
    local file_path=$1
    local file_id=$(echo "$file_path" | md5 | cut -c1-24)
    
    # Check if already exists
    if grep -q "ATPROTO_${file_id} = {isa = PBXBuildFile" "$PROJECT_FILE"; then
        echo "Build file already exists: $file_path"
        return
    fi
    
    # Find the last PBXBuildFile entry and insert after it
    local last_build_line=$(grep -n "/* End PBXBuildFile section */" "$PROJECT_FILE" | cut -d: -f1)
    
    # Create the new entry
    local new_entry="\t\tATPROTO_${file_id} = {isa = PBXBuildFile; fileRef = ATPROTO_${file_id}; };"
    
    # Insert the new entry before the end section
    sed -i '' "${last_build_line}i\\
${new_entry}" "$PROJECT_FILE"
    
    echo "Added build file: $file_path"
}

echo "Adding test files to Xcode project..."

for file in "${TEST_FILES[@]}"; do
    add_file_reference "$file"
    add_build_file "$file"
done

echo "Done!"
