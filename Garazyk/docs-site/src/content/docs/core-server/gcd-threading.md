---
title: Threading with GCD
description: Dispatch queues, synchronization, and advanced concurrency patterns in ATProtoPDS
---

Grand Central Dispatch (GCD) is an extraordinarily robust, low-level multi-core concurrency API
provided natively by the C/Objective-C standard system libraries on Apple platforms. Crucially for
server-side deployments, it has also been fully ported to Linux via `libdispatch`, allowing
cross-platform Objective-C backend applications like our `ATProtoPDS` to cleanly utilize the exact
same high-performance concurrency primitives everywhere without conditional compilation spaghetti.

In our specialized Objective-C backend, we heavily utilize GCD to manage thousands of simultaneous
incoming HTTP XRPC requests, tightly coordinate global WebSocket firehose streams, and absolutely
safeguard concurrent SQLite transactions on the metal instead of manually managing POSIX `pthreads`,
mutexes, or semaphores. GCD radically shifts the programming paradigm from dangerous "thread
management" to clean "queue management", allowing the host operating system kernel to dynamically
scale the thread pool up and down based on real-time system load and CPU availability.

## The Queue Paradigm vs. Threads

Historically, concurrent server programming involved actively creating and managing individual
threads (e.g., raw POSIX threads or `NSThread`). This approach is notoriously difficult: it requires
strictly manual management of thread lifecycles, explicit locks (mutexes) to protect shared memory,
and inevitably leads to subtle race conditions, catastrophic deadlocks, or system-crashing "thread
explosion" under heavy DDoS load.

GCD introduces a vastly superior higher level of abstraction: **Dispatch Queues**. Instead of
commanding the OS to spawn a thread, you cleanly encapsulate work into a C-block (an Objective-C
closure) and seamlessly submit it to a logical queue. The OS kernel aggressively manages a highly
optimized pool of reusable threads behind the scenes and executes the blocks sequentially or
concurrently from those queues onto available physical CPU cores.

This design provides distinct, server-critical advantages:

1. **Efficiency:** Booting an OS thread is incredibly expensive and slow. GCD reuses a warm pool of
   optimized worker threads instantly.
2. **Simplicity:** Engineers focus precisely on _what_ business logic work needs to be done, not
   _how_ to construct the multithreaded engine executing it.
3. **Safety:** Serial queues provide elegant, implicit synchronization without the massive
   context-switching performance overhead or brutal deadlock risks physically associated with
   traditional pthread mutexes.

---

## Dispatch Queues

At its core, GCD abstracts the concept of threads entirely away into "Queues", which cleanly
represent a logical sequence of tasks (closures/blocks) scheduled to execute.

### Serial Queues (The Lock-Free Mutex)

Tasks bound directly to a Serial Queue mathematically execute in strict FIFO (First-In-First-Out)
chronological order, exactly one at a time. Because only one block physically executes at any given
millisecond across the entire server logic, a serial queue elegantly creates an implicit,
un-contended lock.

We rigorously use serial queues specifically for serializing write access to the underlying SQLite
database file handles. While SQLite handles concurrent reader threads gracefully, it structurally
requires absolutely serial writes under its WAL (Write-Ahead Log) mode to prevent corruption. Serial
queues also totally prevent Time-Of-Check to Time-Of-Use (TOCTOU) race conditions when checking if a
user's repository database exists on disk before attempting to dynamically create it.

```objc
// 1. Create a dedicated serial dispatch queue for strictly serialized DB writes
dispatch_queue_t dbWriteQueue = dispatch_queue_create("com.garazyk.pds.db_write", DISPATCH_QUEUE_SERIAL);

// 2. Dispatch the closure asynchronously to the background queue
dispatch_async(dbWriteQueue, ^{
    // 3. This block is mathematically guaranteed by the kernel to be the 
    //    ONLY block modifying this specific database on this queue at this exact moment. 
    //    No complex POSIX mutex locks are required to safely update the row.
    [self executeSqlUpdate:@"INSERT INTO repos ..."];
});
```

> [!CAUTION]
> **Beware of Immediate Deadlocks:** If you are currently executing code physically _on_ a serial
> queue, and you synchronously dispatch (`dispatch_sync`) a second block back onto that _exact same_
> serial queue, your server process will instantly deadlock forever. The queue will infinitely wait
> for the first block to finish before starting the second block, but the first block is physically
> blocked waiting for the second block to finish.

### Concurrent Queues

Tasks explicitly dispatched to a Concurrent Queue are immediately deployed across all available CPU
cores by the OS thread pool. They run simultaneously in parallel. While the tasks themselves are
dequeued off the queue in FIFO order, their physical execution overlaps globally, and they can
finish in absolutely any order based on latency.

For every single incoming HTTP network request off the `accept()` socket within the `PDSHttpServer`
(or the XRPC routing dispatcher), we instantly dispatch the raw networking block to a global
concurrent queue. This prevents the primary listener socket from blocking and allows the server to
simultaneously handle tens of thousands of requests:

```objc
// Instantly grab the host system's global concurrent thread-pool
dispatch_queue_t reqQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

dispatch_async(reqQueue, ^{
    // Process the connected client's HTTP request on a background thread entirely 
    // without blocking the main event runloop.
    [self processClientSocket:clientFd];
});
```

### The Reader-Writer Pattern (`dispatch_barrier`)

When you construct a high-performance in-memory state cache that is read extremely frequently but
strictly written infrequently, a serial queue can quickly become a massive throughput bottleneck.
Concurrent queues offer a highly specialized feature for this exact scenario: **Memory Barriers**.

When a block is dispatched with the `dispatch_barrier_async` function onto a custom concurrent
queue, GCD structurally ensures that this specific block is the _absolute only_ block executing on
that queue across all CPU cores at that time. It pauses and waits for all previously enqueued reader
blocks to cleanly finish, executes the write barrier block exclusively, and then seamlessly resumes
concurrent execution for all subsequently enqueued reader blocks.

```objc
dispatch_queue_t sessionCacheQueue = dispatch_queue_create("com.garazyk.pds.session_cache", DISPATCH_QUEUE_CONCURRENT);

// Concurrent Reads: Thousands of requests can seamlessly read simultaneously
dispatch_sync(sessionCacheQueue, ^{
    Session *activeSession = self.cache[userDid];
});

// Exclusive Write (The Barrier): Only executing when a true mutation happens
dispatch_barrier_async(sessionCacheQueue, ^{
    // This mutating block runs ONLY when all prior active reads cleanly finish.
    // Absolutely no other concurrent reads or writes run simultaneously with this.
    self.cache[userDid] = newLoggedOutSession;
});
```

---

## Dispatch Groups (Gathering Parallel Network Results)

Sometimes an advanced XRPC handler algorithm fundamentally requires reliably fetching the
decentralized DID Document (via a slow HTTP request to the external `plc.directory`), fetching their
network handle from the global AppView, and asynchronously writing an audit log all at the exact
same time before finally replying to the client application.

Doing this sequentially sequentially wastes massive amounts of latency. We use **Dispatch Groups**
(`dispatch_group_t`) to instantly kick off these independent I/O bound tasks completely in parallel
and execute a final, singular "gather" handler when all network branches have finally converged.

```objc
dispatch_group_t group = dispatch_group_create();

// 1. Enter the group and fire off parallel background HTTP tasks
dispatch_group_async(group, concurrentQueue, ^{ 
    [self fetchDidDocumentSynchronously]; 
});
dispatch_group_async(group, concurrentQueue, ^{ 
    [self verifyHandleSynchronously]; 
});

// 2. Instruct the OS kernel to instantly invoke the completion block 
// ONLY when both background tasks cleanly finish and exit.
dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    // Both background HTTP tasks are now completely finished! We can safely proceed.
    [response setBody:@"DID and Handle strictly verified"];
});
```

### Handling Inner Asynchronous Callbacks

A notoriously common server bug with `dispatch_group_async` is that GCD internally considers the
task "finished" the precise millisecond the inner block returns. If your block kicks off an
_asynchronous_ network request (like Apple's `NSURLSession`), the block returns instantly, and the
entire group completes prematurely while the network request is still physically over the wire.

To cleanly handle deep inner asynchronous tasks, you must strictly abandon `dispatch_group_async`
and manually manually manage the group counting using `dispatch_group_enter` and
`dispatch_group_leave`:

```objc
dispatch_group_t group = dispatch_group_create();

// Manually increment the tracking integer
dispatch_group_enter(group);
[self.networkClient fetchAsyncDid:did completion:^(DIDDocument *doc) {
    // Process the securely downloaded doc off the wire
    dispatch_group_leave(group); // Signal completion ONLY when the async callback fires
}];

dispatch_group_enter(group);
[self.networkClient verifyAsyncHandle:handle completion:^(BOOL isValid) {
    // Process handle validity
    dispatch_group_leave(group); // Signal completion ONLY when the async callback fires
}];

dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    // Safely execute the final logic ONLY after BOTH network callbacks have genuinely completed
});
```

> [!IMPORTANT]
> Every single `dispatch_group_enter` must be perfectly, unquestionably balanced with exactly one
> `dispatch_group_leave`. If a complex logic path (like an obscure error handler) accidentally skips
> the leave call, the `dispatch_group_notify` handler block will literally never execute,
> permanently leaking server memory and leaving the client HTTP connection hanging indefinitely.

---

## Limiting Brutal Concurrency with Semaphores

While GCD flawlessly manages the internal thread pool, occasionally you absolutely must artificially
limit concurrency to protect external physical resources—for example, preventing the PDS from
accidentally opening more than 100 simultaneous outgoing TCP socket connections to a fragile remote
relay.

**Dispatch Semaphores** (`dispatch_semaphore_t`) are perfect for this explicit rate-limiting:

```objc
// Create a bounded OS semaphore with a maximum concurrent count of exactly 10
dispatch_semaphore_t connectionSemaphore = dispatch_semaphore_create(10);

dispatch_async(globalQueue, ^{
    // 1. Wait (atomic decrement). If count is 0, this specific thread suspends and blocks 
    //    gracefully until a slot naturally opens up.
    dispatch_semaphore_wait(connectionSemaphore, DISPATCH_TIME_FOREVER);
    
    // 2. Safely perform the highly constrained network work
    [self performHeavyNetworkTask];
    
    // 3. Signal (atomic increment). Seamlessly opens up a slot, instantly waking 
    //    up another suspended waiting thread.
    dispatch_semaphore_signal(connectionSemaphore);
});
```

---

## Conclusion & Server Best Practices

When architecting complex multi-core logic with GCD in an `ATProtoPDS` deployment, heavily adhere to
these strict infrastructure capabilities:

1. **Avoid Thread Explosion:** Be deeply cautious when rapidly dispatching tens of thousands of
   _blocking_ tasks (like synchronous SSD disk I/O) directly to global concurrent queues. The OS
   will frantically spawn new threads to keep up, potentially leading to hundreds of threads heavily
   consuming massive amounts of RAM. Prefer truly asynchronous APIs or decisively cap the
   concurrency with semaphores.
2. **Mind Your ARC Retain Cycles:** Objective-C blocks strongly, implicitly capture variables from
   their enclosing scope. When a Controller class dispatches a block to a queue that captures
   `self`, it creates a fatal retain cycle memory leak if the class also holds a long-lived
   reference to that queue. Always rigorously use `__weak typeof(self) weakSelf = self;` when
   dispatching background tasks that deliberately outlive the immediate method scope.
3. **Target Linux Compatibility:** Remember that GNUstep's open-source `libdispatch` Linux port is
   highly capable for production backends but fundamentally lacks some ultra-modern, niche
   Apple-specific QoS (Quality of Service) flags. Stick to standard priority integers
   (`DISPATCH_QUEUE_PRIORITY_DEFAULT`, `DISPATCH_QUEUE_PRIORITY_HIGH`) and avoid overly complex,
   bleeding-edge `dispatch_source` machinery unless explicitly compiled or thoroughly unit-tested on
   Ubuntu container images.
