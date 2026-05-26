import { assertEquals, assertRejects } from "@std/assert";
import { withCleanupLock } from "./stale_cleanup.ts";

Deno.test("withCleanupLock: prevents concurrent execution of tasks", async () => {
  let concurrencyCount = 0;
  let maxConcurrency = 0;

  const task = async () => {
    concurrencyCount++;
    maxConcurrency = Math.max(maxConcurrency, concurrencyCount);
    // Simulate work
    await new Promise((resolve) => setTimeout(resolve, 50));
    concurrencyCount--;
  };

  // Run two tasks concurrently. The lock file should force them to execute sequentially.
  await Promise.all([
    withCleanupLock(task),
    withCleanupLock(task),
  ]);

  // If the lock worked, max concurrency should be 1 because the second task
  // blocked until the first task finished.
  assertEquals(maxConcurrency, 1);
});

Deno.test("withCleanupLock: releases lock after failure", async () => {
  let taskRan = false;

  const failingTask = async () => {
    throw new Error("Simulated failure");
  };

  const successfulTask = async () => {
    taskRan = true;
  };

  // Run a failing task that throws an exception
  await assertRejects(() => withCleanupLock(failingTask));
  
  // The lock should be released by the finally block, allowing the next task to run successfully
  await withCleanupLock(successfulTask);
  
  assertEquals(taskRan, true);
});
