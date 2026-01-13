/**
 * Test script for Objective-C Runner
 * 
 * Run with: node test.js
 */

const http = require('http');

const API_URL = process.env.API_URL || 'http://localhost:3001';

const testCases = [
    {
        name: 'Hello World',
        code: 'NSLog(@"Hello, World!");',
        expectSuccess: true,
        expectOutput: 'Hello, World!'
    },
    {
        name: 'Variable and string formatting',
        code: `
            NSString *name = @"NSPds";
            NSLog(@"Welcome to %@!", name);
        `,
        expectSuccess: true,
        expectOutput: 'Welcome to NSPds!'
    },
    {
        name: 'Array iteration',
        code: `
            NSArray *items = @[@"one", @"two", @"three"];
            for (NSString *item in items) {
                NSLog(@"%@", item);
            }
        `,
        expectSuccess: true,
        expectOutput: 'one'
    },
    {
        name: 'Syntax error',
        code: 'NSLog(@"Missing semicolon"',
        expectSuccess: false,
        expectPhase: 'compile'
    },
    {
        name: 'Dictionary usage',
        code: `
            NSDictionary *dict = @{@"key": @"value", @"count": @42};
            NSLog(@"Key: %@, Count: %@", dict[@"key"], dict[@"count"]);
        `,
        expectSuccess: true,
        expectOutput: 'Key: value'
    }
];

async function runTest(testCase) {
    const response = await fetch(`${API_URL}/api/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: testCase.code, timeout: 5 })
    });

    const result = await response.json();

    let passed = true;
    let message = '';

    if (testCase.expectSuccess !== undefined) {
        if (result.success !== testCase.expectSuccess) {
            passed = false;
            message += `Expected success=${testCase.expectSuccess}, got ${result.success}. `;
        }
    }

    if (testCase.expectOutput && result.stdout) {
        if (!result.stdout.includes(testCase.expectOutput)) {
            passed = false;
            message += `Expected output to contain "${testCase.expectOutput}". `;
        }
    }

    if (testCase.expectPhase && result.phase !== testCase.expectPhase) {
        passed = false;
        message += `Expected phase=${testCase.expectPhase}, got ${result.phase}. `;
    }

    return { ...testCase, passed, message, result };
}

async function main() {
    console.log('🧪 Testing Objective-C Runner\n');
    console.log(`API: ${API_URL}\n`);

    let passCount = 0;
    let failCount = 0;

    for (const testCase of testCases) {
        try {
            const result = await runTest(testCase);

            if (result.passed) {
                console.log(`✅ ${result.name}`);
                passCount++;
            } else {
                console.log(`❌ ${result.name}`);
                console.log(`   ${result.message}`);
                console.log(`   Output: ${JSON.stringify(result.result).slice(0, 200)}`);
                failCount++;
            }
        } catch (error) {
            console.log(`❌ ${testCase.name}`);
            console.log(`   Error: ${error.message}`);
            failCount++;
        }
    }

    console.log(`\n📊 Results: ${passCount} passed, ${failCount} failed`);
    process.exit(failCount > 0 ? 1 : 0);
}

main();
