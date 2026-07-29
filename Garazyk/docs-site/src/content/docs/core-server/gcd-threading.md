---
title: Threading with GCD
description: Dispatch queues, synchronization, and bounded concurrency in Garazyk PDS
---

Garazyk uses Grand Central Dispatch (GCD) for work scheduling and
synchronization. Apple platforms provide GCD in the system SDK; Linux builds use
`libdispatch`. The shared API lets most server code use the same queue
primitives on both platforms.

## Dispatch Queues

Callers submit blocks to queues instead of creating threads. The runtime
schedules those blocks on its worker pool.

### Serial queues

One block at a time executes on a serial queue. Garazyk uses serial queues where
operations must keep a defined order, including access to serial SQLite
connection managers.

```objc
dispatch_queue_t dbWriteQueue = dispatch_queue_create("com.garazyk.pds.db_write", DISPATCH_QUEUE_SERIAL);

dispatch_async(dbWriteQueue, ^{
    // No other block submitted to dbWriteQueue executes at the same time.
    [self executeSqlUpdate:@"INSERT INTO repos ..."];
});
```

> [!CAUTION]
> Calling `dispatch_sync` on the same serial queue that is executing the caller
> deadlocks. Preserve each queue's entry contract and use queue-specific
> assertions when a component provides them.

### Concurrent Queues

Blocks on a concurrent queue may overlap and may finish out of order. A
concurrent queue is useful for independent work, but it does not make shared
state safe.

```objc
dispatch_queue_t reqQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

dispatch_async(reqQueue, ^{
    // This work does not block the listener's calling thread.
    [self processClientSocket:clientFd];
});
```

### The Reader-Writer Pattern (`dispatch_barrier`)

Barrier blocks provide exclusive access on a custom concurrent queue. Earlier
blocks finish before the barrier starts, and later blocks wait until it
completes. Barriers on global queues do not provide this exclusivity.

```objc
dispatch_queue_t sessionCacheQueue = dispatch_queue_create("com.garazyk.pds.session_cache", DISPATCH_QUEUE_CONCURRENT);

// Reads may overlap.
dispatch_sync(sessionCacheQueue, ^{
    Session *activeSession = self.cache[userDid];
});

// The mutation runs without another block from this queue.
dispatch_barrier_async(sessionCacheQueue, ^{
    self.cache[userDid] = newLoggedOutSession;
});
```

## Dispatch groups

A dispatch group coordinates independent operations and invokes a completion
block after all of them leave the group.

```objc
dispatch_group_t group = dispatch_group_create();

dispatch_group_async(group, concurrentQueue, ^{
    [self fetchDidDocumentSynchronously];
});
dispatch_group_async(group, concurrentQueue, ^{
    [self verifyHandleSynchronously];
});

dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    [response setBody:@"DID and handle verified"];
});
```

### Asynchronous callbacks

`dispatch_group_async` tracks the submitted block, not work that the block
starts and then abandons. Use explicit enter and leave calls when the operation
completes in a later callback:

```objc
dispatch_group_t group = dispatch_group_create();

dispatch_group_enter(group);
[self.networkClient fetchAsyncDid:did completion:^(DIDDocument *doc) {
    dispatch_group_leave(group);
}];

dispatch_group_enter(group);
[self.networkClient verifyAsyncHandle:handle completion:^(BOOL isValid) {
    dispatch_group_leave(group);
}];

dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    // Both callbacks have left the group.
});
```

> [!IMPORTANT]
> Every successful `dispatch_group_enter` needs exactly one
> `dispatch_group_leave`, including error and cancellation paths. An unmatched
> enter prevents the notification block from running.

## Bounded concurrency with semaphores

A dispatch semaphore can bound access to a scarce resource. Do not wait on a
semaphore from a queue whose work must run to signal it.

```objc
dispatch_semaphore_t connectionSemaphore = dispatch_semaphore_create(10);

dispatch_async(globalQueue, ^{
    dispatch_semaphore_wait(connectionSemaphore, DISPATCH_TIME_FOREVER);
    [self performHeavyNetworkTask];
    dispatch_semaphore_signal(connectionSemaphore);
});
```

## Project rules

- Keep blocking I/O off unbounded global queues. Use an asynchronous API or an
  explicit concurrency limit.
- Document each component's queue ownership and whether public methods may be
  called from any queue.
- Balance group and semaphore operations on every exit path.
- Use weak captures only when the ownership graph requires them; promote the
  weak reference once at the start of the block.
- Test dispatch APIs on both Darwin and GNUstep/Linux before relying on
  platform-specific behavior.
