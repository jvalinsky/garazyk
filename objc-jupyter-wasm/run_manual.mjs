import fs from "fs";
import { createObjcKernel } from "./tests/objc-kernel-test-harness.mjs";

const wasmPath = "result/wasm/kernel.wasm";
const testCode = `
@interface IvarTest : NSObject {
@public int field;
}
@end
@implementation IvarTest
- (instancetype)init { self = [super init]; field = 42; return self; }
@end
IvarTest *t = [IvarTest new];
NSLog(@"%d", t->field);
`;

(async function () {
  const kernel = await createObjcKernel(wasmPath);
  const result = kernel.execute(testCode);
  console.log("Result:", result);
})();
