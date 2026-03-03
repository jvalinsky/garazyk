#!/usr/bin/env python3
"""
Simple Python-based documentation site builder.
Generates static HTML from markdown files.
"""

import os
import sys
import shutil
import markdown
from pathlib import Path
from datetime import datetime

# Configuration
DOCS_DIR = Path(__file__).parent.parent / "docs"
BUILD_DIR = DOCS_DIR / "_site"
MARKDOWN_EXTENSIONS = ['extra', 'toc', 'codehilite', 'tables']

# HTML Template
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} - PDS Objective-C Implementation Guide</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            display: grid;
            grid-template-columns: 250px 1fr;
            gap: 20px;
            padding: 20px;
        }}
        
        .sidebar {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            height: fit-content;
            position: sticky;
            top: 20px;
        }}
        
        .sidebar h3 {{
            margin-bottom: 15px;
            font-size: 14px;
            text-transform: uppercase;
            color: #666;
        }}
        
        .sidebar ul {{
            list-style: none;
        }}
        
        .sidebar li {{
            margin-bottom: 8px;
        }}
        
        .sidebar a {{
            color: #0066cc;
            text-decoration: none;
            font-size: 14px;
        }}
        
        .sidebar a:hover {{
            text-decoration: underline;
        }}
        
        .content {{
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        
        h1 {{
            margin-bottom: 20px;
            color: #222;
            border-bottom: 3px solid #0066cc;
            padding-bottom: 10px;
        }}
        
        h2 {{
            margin-top: 30px;
            margin-bottom: 15px;
            color: #333;
        }}
        
        h3 {{
            margin-top: 20px;
            margin-bottom: 10px;
            color: #555;
        }}
        
        p {{
            margin-bottom: 15px;
        }}
        
        code {{
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 14px;
        }}
        
        pre {{
            background: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            margin-bottom: 15px;
            border-left: 4px solid #0066cc;
        }}
        
        pre code {{
            background: none;
            padding: 0;
        }}
        
        ul, ol {{
            margin-left: 20px;
            margin-bottom: 15px;
        }}
        
        li {{
            margin-bottom: 8px;
        }}
        
        a {{
            color: #0066cc;
            text-decoration: none;
        }}
        
        a:hover {{
            text-decoration: underline;
        }}
        
        table {{
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 15px;
        }}
        
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        
        th {{
            background: #f4f4f4;
            font-weight: bold;
        }}
        
        .toc {{
            background: #f9f9f9;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }}
        
        .toc ul {{
            margin-left: 15px;
        }}
        
        .header {{
            background: #0066cc;
            color: white;
            padding: 20px;
            margin: -20px -20px 20px -20px;
            border-radius: 8px 8px 0 0;
        }}
        
        .header h1 {{
            border: none;
            padding: 0;
            margin: 0;
            color: white;
        }}
        
        .footer {{
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 12px;
            margin-top: 40px;
            border-top: 1px solid #eee;
        }}
        
        @media (max-width: 768px) {{
            .container {{
                grid-template-columns: 1fr;
            }}
            
            .sidebar {{
                position: static;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="sidebar">
            <h3>Navigation</h3>
            <ul>
                <li><a href="index.html">Home</a></li>
                <li><a href="SUMMARY.html">Table of Contents</a></li>
                <li><a href="GLOSSARY.html">Glossary</a></li>
            </ul>
            
            <h3 style="margin-top: 20px;">Sections</h3>
            <ul>
                <li><a href="01-getting-started/overview.html">Getting Started</a></li>
                <li><a href="02-core-concepts/cbor-and-car.html">Core Concepts</a></li>
                <li><a href="03-application-layer/pds-application.html">Application Layer</a></li>
                <li><a href="04-network-layer/http-server.html">Network Layer</a></li>
                <li><a href="05-database-layer/sqlite-architecture.html">Database Layer</a></li>
                <li><a href="06-authentication/jwt-tokens.html">Authentication</a></li>
                <li><a href="07-repository-protocol/repository-basics.html">Repository & Protocol</a></li>
                <li><a href="08-sync-firehose/firehose-overview.html">Sync & Firehose</a></li>
                <li><a href="09-platform-compatibility/macos-linux.html">Platform Compatibility</a></li>
                <li><a href="10-tutorials/tutorial-1-hello-pds.html">Tutorials</a></li>
                <li><a href="11-reference/api-reference.html">Reference</a></li>
            </ul>
        </div>
        
        <div class="content">
            <div class="header">
                <h1>{title}</h1>
            </div>
            {content}
            <div class="footer">
                <p>PDS Objective-C Implementation Guide | Built {timestamp}</p>
            </div>
        </div>
    </div>
</body>
</html>
"""

def ensure_dir(path):
    """Ensure directory exists."""
    path.mkdir(parents=True, exist_ok=True)

def convert_markdown_to_html(md_content):
    """Convert markdown to HTML."""
    md = markdown.Markdown(extensions=MARKDOWN_EXTENSIONS)
    html = md.convert(md_content)
    return html

def get_title_from_markdown(md_content):
    """Extract title from markdown (first H1)."""
    lines = md_content.split('\n')
    for line in lines:
        if line.startswith('# '):
            return line[2:].strip()
    return "Documentation"

def build_site():
    """Build the documentation site."""
    print("Building documentation site...")
    
    # Clean build directory
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    ensure_dir(BUILD_DIR)
    
    # Copy assets
    assets_src = DOCS_DIR / "assets"
    if assets_src.exists():
        assets_dst = BUILD_DIR / "assets"
        shutil.copytree(assets_src, assets_dst)
        print(f"✓ Copied assets")
    
    # Process markdown files
    md_files = list(DOCS_DIR.glob("**/*.md"))
    print(f"Found {len(md_files)} markdown files")
    
    for md_file in sorted(md_files):
        # Skip files in subdirectories we don't want to process
        if any(part in md_file.parts for part in ['archive', 'development', 'guides', 'oauth2', 'plan', 'plans', 'security', 'session-reports', 'site', 'skills', 'tests']):
            continue
        
        # Read markdown
        with open(md_file, 'r', encoding='utf-8') as f:
            md_content = f.read()
        
        # Convert to HTML
        html_content = convert_markdown_to_html(md_content)
        title = get_title_from_markdown(md_content)
        
        # Generate HTML
        html = HTML_TEMPLATE.format(
            title=title,
            content=html_content,
            timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        )
        
        # Determine output path
        rel_path = md_file.relative_to(DOCS_DIR)
        html_file = BUILD_DIR / rel_path.with_suffix('.html')
        ensure_dir(html_file.parent)
        
        # Write HTML
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(html)
        
        print(f"✓ {rel_path} → {html_file.relative_to(BUILD_DIR)}")
    
    print(f"\n✓ Documentation built successfully!")
    print(f"✓ Output directory: {BUILD_DIR}")
    print(f"\nTo view the site, open: {BUILD_DIR / 'index.html'}")
    
    return True

if __name__ == "__main__":
    try:
        success = build_site()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"✗ Error building documentation: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
