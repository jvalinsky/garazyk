#!/usr/bin/env tsx

/**
 * Find YAML Front Matter Errors
 * 
 * Identifies files with problematic YAML front matter
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';
import * as yaml from 'js-yaml';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

interface YAMLError {
  file: string;
  error: string;
  frontMatter: string;
}

const errors: YAMLError[] = [];

async function checkFile(filepath: string): Promise<void> {
  const content = fs.readFileSync(filepath, 'utf-8');
  
  // Check if file has front matter
  if (!content.startsWith('---\n')) {
    return;
  }
  
  // Extract front matter
  const endIndex = content.indexOf('\n---\n', 4);
  if (endIndex === -1) {
    errors.push({
      file: path.relative(DOCS_DIR, filepath),
      error: 'Unclosed front matter',
      frontMatter: content.substring(0, 100)
    });
    return;
  }
  
  const frontMatter = content.substring(4, endIndex);
  
  // Try to parse YAML
  try {
    yaml.load(frontMatter);
  } catch (error: any) {
    errors.push({
      file: path.relative(DOCS_DIR, filepath),
      error: error.message,
      frontMatter: frontMatter.substring(0, 200)
    });
  }
}

async function main(): Promise<void> {
  console.log('🔍 Checking YAML front matter...\n');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: [
      '**/node_modules/**',
      '**/.vitepress/cache/**',
      '**/.vitepress/dist/**'
    ]
  });
  
  for (const filepath of files) {
    await checkFile(filepath);
  }
  
  if (errors.length === 0) {
    console.log('✅ No YAML errors found!\n');
  } else {
    console.log(`❌ Found ${errors.length} YAML errors:\n`);
    
    for (const error of errors) {
      console.log(`File: ${error.file}`);
      console.log(`Error: ${error.error}`);
      console.log(`Front matter preview:`);
      console.log(error.frontMatter);
      console.log('---\n');
    }
  }
}

main();
