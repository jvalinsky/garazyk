#!/usr/bin/env python3
"""
Test links specifically in the PDS Implementation Guide (sections 01-12).

This focuses on the new documentation structure and ignores legacy docs.
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Tuple, Set
from urllib.parse import urlparse, unquote

class PDSGuideLinkTester:
    def __init__(self, docs_dir: str, repo_root: str):
        self.docs_dir = Path(docs_dir)
        self.repo_root = Path(repo_root)
        self.errors = []
        self.warnings = []
        self.checked_files = set()
        
        # Only check these directories (PDS Implementation Guide)
        self.include_dirs = [
            '01-getting-started',
            '02-core-concepts',
            '03-application-layer',
            '04-network-layer',
            '05-database-layer',
            '06-authentication',
            '07-repository-protocol',
            '08-sync-firehose',
            '09-platform-compatibility',
            '10-tutorials',
            '11-reference',
            '12-diagrams'
        ]
        
        # Also check these root files
        self.include_root_files = [
            'index.md',
            'SUMMARY.md',
            'GLOSSARY.md'
        ]
        
    def should_check_file(self, file_path: Path) -> bool:
        """Determine if a file should be checked."""
        rel_path = file_path.relative_to(self.docs_dir)
        
        # Check root files
        if str(rel_path) in self.include_root_files:
            return True
            
        # Check if in one of the included directories
        parts = rel_path.parts
        if len(parts) > 0 and parts[0] in self.include_dirs:
            return True
            
        return False
        
    def log_error(self, file_path: str, line_num: int, message: str):
        """Log an error with file and line number."""
        self.errors.append(f"{file_path}:{line_num}: ERROR: {message}")
        
    def log_warning(self, file_path: str, line_num: int, message: str):
        """Log a warning with file and line number."""
        self.warnings.append(f"{file_path}:{line_num}: WARNING: {message}")
        
    def extract_markdown_links(self, content: str) -> List[Tuple[int, str, str]]:
        """Extract all markdown links from content."""
        links = []
        lines = content.split('\n')
        
        # Match [text](url) and [text](url#anchor)
        link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
        
        for line_num, line in enumerate(lines, 1):
            for match in link_pattern.finditer(line):
                link_text = match.group(1)
                link_url = match.group(2)
                links.append((line_num, link_text, link_url))
                
        return links
        
    def extract_anchors(self, content: str) -> Set[str]:
        """Extract all heading anchors from markdown content."""
        anchors = set()
        lines = content.split('\n')
        
        # Match markdown headings
        heading_pattern = re.compile(r'^#+\s+(.+)$')
        
        for line in lines:
            match = heading_pattern.match(line)
            if match:
                heading_text = match.group(1)
                # Convert to anchor format (GitHub/Jekyll style)
                anchor = heading_text.lower()
                # Remove special characters except spaces and hyphens
                anchor = re.sub(r'[^\w\s-]', '', anchor)
                # Replace spaces with hyphens
                anchor = re.sub(r'\s+', '-', anchor)
                anchors.add(anchor)
                
        return anchors
        
    def check_file_exists(self, file_path: Path) -> bool:
        """Check if a file exists."""
        return file_path.exists() and file_path.is_file()
        
    def resolve_link(self, source_file: Path, link_url: str) -> Tuple[Path, str]:
        """Resolve a link URL to an absolute path and anchor."""
        # Parse URL to separate path and anchor
        if '#' in link_url:
            path_part, anchor = link_url.split('#', 1)
        else:
            path_part, anchor = link_url, None
            
        # Skip external URLs
        if path_part.startswith(('http://', 'https://', 'mailto:')):
            return None, None
            
        # Resolve relative path
        if path_part:
            # Decode URL encoding
            path_part = unquote(path_part)
            
            # Resolve relative to source file's directory
            source_dir = source_file.parent
            resolved = (source_dir / path_part).resolve()
        else:
            # Anchor-only link refers to current file
            resolved = source_file
            
        return resolved, anchor
        
    def test_link(self, source_file: Path, line_num: int, link_text: str, link_url: str):
        """Test a single link."""
        # Skip external URLs
        if link_url.startswith(('http://', 'https://', 'mailto:')):
            return
            
        # Resolve the link
        target_path, anchor = self.resolve_link(source_file, link_url)
        
        if target_path is None:
            return  # External URL, already skipped
            
        # Check if target file exists
        if not self.check_file_exists(target_path):
            self.log_error(
                str(source_file.relative_to(self.repo_root)),
                line_num,
                f"Broken link: '{link_url}' -> target not found: {target_path.name}"
            )
            return
            
        # If there's an anchor, check if it exists in the target file
        if anchor:
            # Only check anchors in markdown files
            if target_path.suffix == '.md':
                try:
                    with open(target_path, 'r', encoding='utf-8') as f:
                        target_content = f.read()
                    target_anchors = self.extract_anchors(target_content)
                    
                    if anchor not in target_anchors:
                        self.log_error(
                            str(source_file.relative_to(self.repo_root)),
                            line_num,
                            f"Broken anchor: '{link_url}' -> anchor '#{anchor}' not found in {target_path.name}"
                        )
                        # Show available anchors for debugging
                        if target_anchors:
                            available = ', '.join(sorted(list(target_anchors)[:5]))
                            self.log_warning(
                                str(source_file.relative_to(self.repo_root)),
                                line_num,
                                f"Available anchors in {target_path.name}: {available}..."
                            )
                except Exception as e:
                    self.log_warning(
                        str(source_file.relative_to(self.repo_root)),
                        line_num,
                        f"Could not read target file {target_path}: {e}"
                    )
                    
    def test_file(self, file_path: Path):
        """Test all links in a single markdown file."""
        if file_path in self.checked_files:
            return
            
        self.checked_files.add(file_path)
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            self.log_error(
                str(file_path.relative_to(self.repo_root)),
                0,
                f"Could not read file: {e}"
            )
            return
            
        # Extract and test all links
        links = self.extract_markdown_links(content)
        for line_num, link_text, link_url in links:
            self.test_link(file_path, line_num, link_text, link_url)
            
    def test_pds_guide(self):
        """Test all markdown files in the PDS Implementation Guide."""
        # Find all markdown files
        md_files = list(self.docs_dir.rglob('*.md'))
        
        # Filter to only PDS Guide files
        pds_files = [f for f in md_files if self.should_check_file(f)]
        
        print(f"Testing {len(pds_files)} PDS Implementation Guide files...")
        
        for md_file in sorted(pds_files):
            rel_path = md_file.relative_to(self.docs_dir)
            print(f"  Checking {rel_path}")
            self.test_file(md_file)
            
    def print_results(self):
        """Print test results."""
        print("\n" + "="*80)
        print("PDS IMPLEMENTATION GUIDE - LINK TESTING RESULTS")
        print("="*80)
        
        if self.errors:
            print(f"\n❌ Found {len(self.errors)} errors:\n")
            for error in self.errors:
                print(f"  {error}")
        else:
            print("\n✅ No errors found!")
            
        if self.warnings:
            print(f"\n⚠️  Found {len(self.warnings)} warnings:\n")
            for warning in self.warnings:
                print(f"  {warning}")
                
        print(f"\nChecked {len(self.checked_files)} files")
        print("="*80)
        
        return len(self.errors) == 0

def main():
    # Determine repository root and docs directory
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    docs_dir = repo_root / 'docs'
    
    if not docs_dir.exists():
        print(f"Error: docs directory not found at {docs_dir}")
        sys.exit(1)
        
    # Run tests
    tester = PDSGuideLinkTester(str(docs_dir), str(repo_root))
    tester.test_pds_guide()
    
    # Print results
    success = tester.print_results()
    
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
