/**
 * Migration Configuration Schema
 *
 * Defines the structure and validation rules for migration configuration files.
 * A migration config specifies how to move documentation files from source
 * directories to destination directories while preserving git history.
 */

/**
 * JSON Schema for migration configuration
 *
 * @type {Object}
 */
export const migrationConfigSchema = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  type: 'object',
  required: ['version', 'migrations'],
  properties: {
    version: {
      type: 'string',
      pattern: '^\\d+\\.\\d+\\.\\d+$',
      description: 'Semantic version of the migration configuration format'
    },
    description: {
      type: 'string',
      description: 'Human-readable description of this migration configuration'
    },
    migrations: {
      type: 'array',
      minItems: 1,
      description: 'Array of migration operations to perform',
      items: {
        type: 'object',
        required: ['source', 'destination'],
        properties: {
          source: {
            type: 'string',
            minLength: 1,
            description: 'Source directory path (relative to repository root)'
          },
          destination: {
            type: 'string',
            minLength: 1,
            description: 'Destination directory path (relative to repository root)'
          },
          filePatterns: {
            type: 'array',
            description: 'Glob patterns for files to include (default: ["**/*"])',
            items: {
              type: 'string',
              minLength: 1
            },
            default: ['**/*']
          },
          excludePatterns: {
            type: 'array',
            description: 'Glob patterns for files to exclude',
            items: {
              type: 'string',
              minLength: 1
            },
            default: [
              '**/.git/**',
              '**/node_modules/**',
              '**/.DS_Store',
              '**/Thumbs.db'
            ]
          },
          preserveStructure: {
            type: 'boolean',
            description: 'Whether to preserve directory structure from source (default: true)',
            default: true
          },
          updateReferences: {
            type: 'boolean',
            description: 'Whether to update cross-references in moved files (default: true)',
            default: true
          },
          removeEmptyDirs: {
            type: 'boolean',
            description: 'Whether to remove empty source directories after migration (default: true)',
            default: true
          }
        },
        additionalProperties: false
      }
    },
    options: {
      type: 'object',
      description: 'Global migration options',
      properties: {
        dryRun: {
          type: 'boolean',
          description: 'Perform a dry run without making actual changes (default: false)',
          default: false
        },
        verbose: {
          type: 'boolean',
          description: 'Enable verbose logging (default: false)',
          default: false
        },
        generateReport: {
          type: 'boolean',
          description: 'Generate a migration report file (default: true)',
          default: true
        },
        reportPath: {
          type: 'string',
          description: 'Path for the migration report file (default: "migration-report.json")',
          default: 'migration-report.json'
        },
        mappingPath: {
          type: 'string',
          description: 'Path for the migration mapping file (default: "migration-mapping.json")',
          default: 'migration-mapping.json'
        },
        continueOnError: {
          type: 'boolean',
          description: 'Continue migration even if some files fail (default: false)',
          default: false
        }
      },
      additionalProperties: false
    }
  },
  additionalProperties: false
};

/**
 * Validation error class for migration configuration
 */
export class MigrationConfigError extends Error {
  constructor(message, errors = []) {
    super(message);
    this.name = 'MigrationConfigError';
    this.errors = errors;
  }
}

/**
 * Validates a value against a schema property
 *
 * @param {*} value - Value to validate
 * @param {Object} schema - Schema property definition
 * @param {string} path - Path to this value in the config (for error messages)
 * @returns {Array<string>} Array of error messages (empty if valid)
 */
function validateProperty(value, schema, path) {
  const errors = [];

  // Check required type
  if (schema.type) {
    const actualType = Array.isArray(value) ? 'array' : typeof value;
    if (actualType !== schema.type) {
      errors.push(`${path}: expected type ${schema.type}, got ${actualType}`);
      return errors; // Type mismatch, skip further validation
    }
  }

  // Validate based on type
  switch (schema.type) {
  case 'string':
    if (schema.minLength && value.length < schema.minLength) {
      errors.push(`${path}: string length must be at least ${schema.minLength}`);
    }
    if (schema.pattern) {
      const regex = new RegExp(schema.pattern);
      if (!regex.test(value)) {
        errors.push(`${path}: string does not match pattern ${schema.pattern}`);
      }
    }
    break;

  case 'array':
    if (schema.minItems && value.length < schema.minItems) {
      errors.push(`${path}: array must have at least ${schema.minItems} items`);
    }
    if (schema.items) {
      value.forEach((item, index) => {
        errors.push(...validateProperty(item, schema.items, `${path}[${index}]`));
      });
    }
    break;

  case 'object':
    // Check required properties
    if (schema.required) {
      schema.required.forEach((requiredProp) => {
        if (!(requiredProp in value)) {
          errors.push(`${path}: missing required property '${requiredProp}'`);
        }
      });
    }

    // Validate each property
    if (schema.properties) {
      Object.keys(value).forEach((key) => {
        if (schema.properties[key]) {
          errors.push(...validateProperty(
            value[key],
            schema.properties[key],
            `${path}.${key}`
          ));
        } else if (schema.additionalProperties === false) {
          errors.push(`${path}: unexpected property '${key}'`);
        }
      });
    }
    break;
  }

  return errors;
}

/**
 * Validates a migration configuration object against the schema
 *
 * @param {Object} config - Migration configuration to validate
 * @returns {Object} Validation result with { valid: boolean, errors: Array<string> }
 */
export function validateMigrationConfig(config) {
  const errors = [];

  // Check if config is an object
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    return {
      valid: false,
      errors: ['Configuration must be an object']
    };
  }

  // Validate against schema
  errors.push(...validateProperty(config, migrationConfigSchema, 'config'));

  // Additional semantic validations
  if (config.migrations) {
    config.migrations.forEach((migration, index) => {
      // Skip semantic validation if required fields are missing
      if (!migration.source || !migration.destination) {
        return;
      }

      // Check for duplicate source directories
      const duplicates = config.migrations.filter(
        (m, i) => i !== index && m.source === migration.source
      );
      if (duplicates.length > 0) {
        errors.push(
          `config.migrations[${index}]: duplicate source directory '${migration.source}'`
        );
      }

      // Check for source === destination
      if (migration.source === migration.destination) {
        errors.push(
          `config.migrations[${index}]: source and destination cannot be the same`
        );
      }

      // Check for nested paths (destination inside source or vice versa)
      if (migration.destination.startsWith(`${migration.source}/`)) {
        errors.push(
          `config.migrations[${index}]: destination '${migration.destination}' ` +
          `is inside source '${migration.source}'`
        );
      }
      if (migration.source.startsWith(`${migration.destination}/`)) {
        errors.push(
          `config.migrations[${index}]: source '${migration.source}' ` +
          `is inside destination '${migration.destination}'`
        );
      }
    });
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

/**
 * Loads and validates a migration configuration from a file
 *
 * @param {string} configPath - Path to the configuration file
 * @returns {Promise<Object>} Validated configuration object
 * @throws {MigrationConfigError} If configuration is invalid
 */
export async function loadMigrationConfig(configPath) {
  const fs = await import('fs-extra');

  // Check if file exists
  if (!await fs.default.pathExists(configPath)) {
    throw new MigrationConfigError(
      `Configuration file not found: ${configPath}`
    );
  }

  // Read and parse configuration
  let config;
  try {
    const content = await fs.default.readFile(configPath, 'utf8');
    config = JSON.parse(content);
  } catch (error) {
    throw new MigrationConfigError(
      `Failed to parse configuration file: ${error.message}`
    );
  }

  // Validate configuration
  const validation = validateMigrationConfig(config);
  if (!validation.valid) {
    throw new MigrationConfigError(
      'Invalid migration configuration',
      validation.errors
    );
  }

  // Apply defaults
  config.migrations = config.migrations.map((migration) => ({
    filePatterns: ['**/*'],
    excludePatterns: [
      '**/.git/**',
      '**/node_modules/**',
      '**/.DS_Store',
      '**/Thumbs.db'
    ],
    preserveStructure: true,
    updateReferences: true,
    removeEmptyDirs: true,
    ...migration
  }));

  config.options = {
    dryRun: false,
    verbose: false,
    generateReport: true,
    reportPath: 'migration-report.json',
    mappingPath: 'migration-mapping.json',
    continueOnError: false,
    ...config.options
  };

  return config;
}
