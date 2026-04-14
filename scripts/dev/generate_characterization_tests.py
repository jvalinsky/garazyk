#!/usr/bin/env python3
import argparse
import os
import re
import sys

def parse_header(header_path):
    with open(header_path, 'r') as f:
        content = f.read()

    # Regex for finding interfaces
    # Capture the class name
    interface_pattern = re.compile(r'@interface\s+(\w+)\s*:')
    
    classes = {}
    
    # helper to parse methods inside an @interface ... @end block?
    # Actually, simpler to just scan the whole file for @implementation or @interface and methods.
    # But headers usually validly separate them.
    
    # Let's iterate over the file and track which class we are in.
    # But often interfaces are defined sequentially.
    
    # Simplified approach: Extract blocks for each interface
    # This is hard with regex.
    # Failure mode: just find all methods and try to guess? No.
    
    # Better approach:
    # 1. Find all `@interface Name : Super`
    # 2. Find the END of that block (next @interface or @citation or @end)
    # 3. Parse methods within that chunk.
    
    # Let's try to match `@interface ... @end` blocks loosely.
    
    # split by @interface
    chunks = re.split(r'(@interface\s+\w+)', content)
    
    current_class = None
    
    for chunk in chunks:
        # Check if this chunk is the start of a class definition
        class_match = re.match(r'@interface\s+(\w+)', chunk)
        if class_match:
             # This chunk IS the marker, the NEXT chunk is the content
             current_class = class_match.group(1)
             continue
             
        if current_class:
            # This chunk contains the body of current_class
            # Parse methods
            
            # Instance methods (-) and Class methods (+)
            method_pattern = re.compile(r'^\s*([+-])\s*\(([^)]+)\)([^;]+);', re.MULTILINE)
            
            cls_methods = []
            for match in method_pattern.finditer(chunk):
                kind = match.group(1) # + or -
                return_type = match.group(2).strip()
                signature_raw = match.group(3).strip()
                
                parts = signature_raw.split(':')
                first_part = parts[0].strip()
                
                cls_methods.append({
                    'kind': kind,
                    'return_type': return_type,
                    'full_text': match.group(0).strip(),
                    'name': first_part
                })
            
            classes[current_class] = cls_methods
            current_class = None # Reset
            
    return classes

def generate_test_content(class_name, methods, header_path):
    # Determine looking relative path for import
    # header_path is absolute. We need to find where it is relative to Sources/
    
    import_path = header_path
    if "Garazyk/Sources/" in header_path:
        import_path = header_path.split("Garazyk/Sources/")[1]
    
    content = f"""#import "CharacterizationTestBase.h"
#import "{import_path}"

@interface {class_name}CharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) {class_name} *subject;

@end

@implementation {class_name}CharacterizationTests

- (void)setUp {{
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[{class_name} alloc] init];
}}

- (void)tearDown {{
    self.subject = nil;
    [super tearDown];
}}

/*
 * Characterization Tests for {class_name}
 * Generated automatically. Please implement specific scenarios.
 */
"""

    seen_methods = set()
    for method in methods:
        method_name = method['name']
        kind_prefix = "Class_" if method['kind'] == '+' else ""
        test_method_name = f"testCharacterization_{kind_prefix}{method_name}"
        
        # Handle overloads/duplicates in naming
        counter = 1
        base_name = test_method_name
        while test_method_name in seen_methods:
            counter += 1
            test_method_name = f"{base_name}_{counter}"
        seen_methods.add(test_method_name)
        
        act_line = ""
        if method['kind'] == '+':
            act_line = f"// [{class_name} {method_name}...];"
        else:
            act_line = f"// [self.subject {method_name}...];"

        content += f"""
- (void){test_method_name} {{
    /* Target Method:
     {method['full_text']}
    */
    
    // 1. Arrange
    
    // 2. Act
    {act_line}
    
    // 3. Assert
    // XCTFail(@"Test not implemented");
}}
"""

    content += "\n@end\n"
    return content

def main():
    parser = argparse.ArgumentParser(description='Generate characterization tests for a class.')
    parser.add_argument('header', help='Path to the header file of the class')
    parser.add_argument('--output', help='Output directory for the test file', default='Garazyk/Tests/CharacterizationTests')
    parser.add_argument('--target-class', help='Specific class to generate tests for', default=None)
    
    args = parser.parse_args()
    
    if not os.path.exists(args.header):
        print(f"Error: Header file not found: {args.header}")
        sys.exit(1)
        
    classes = parse_header(args.header)
    
    if not classes:
        print("Error: Could not find any @interface definitions in header.")
        sys.exit(1)
        
    # Determine target class
    target = args.target_class
    if not target:
        # derive from filename
        basename = os.path.basename(args.header)
        root = os.path.splitext(basename)[0]
        if root in classes:
            target = root
        else:
            # Pick the first one if exact match not found?
            # Or just warn?
            # Let's pick the one with the most methods? 
            # Or just the first one found.
            target = list(classes.keys())[0]
            print(f"Warning: Class '{root}' not found in header. Defaulting to '{target}'.")
            
    if target not in classes:
        print(f"Error: Target class '{target}' not found in {list(classes.keys())}")
        sys.exit(1)
        
    methods = classes[target]
    print(f"Generating tests for class: {target} with {len(methods)} methods.")
    
    test_content = generate_test_content(target, methods, args.header)
    
    output_filename = f"{target}CharacterizationTests.m"
    output_path = os.path.join(args.output, output_filename)
    
    # Create directory if it doesn't exist
    os.makedirs(args.output, exist_ok=True)
    
    if os.path.exists(output_path):
        print(f"Warning: {output_path} already exists. Skipping generation to avoid overwrite.")
    else:
        with open(output_path, 'w') as f:
            f.write(test_content)
        print(f"Generated {output_path}")

if __name__ == '__main__':
    main()
