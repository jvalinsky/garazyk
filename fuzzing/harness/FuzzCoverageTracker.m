// FuzzCoverageTracker.m - Simple coverage tracking wrapper

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

static uint64_t g_totalExecutions = 0;
static uint64_t g_coverageHits = 0;
static uint32_t g_startTime = 0;
static uint64_t g_maxRuns = 0;

__attribute__((noinline))
void FuzzCoverageInit(uint64_t maxRuns) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    g_startTime = tv.tv_sec;
    g_maxRuns = maxRuns;
    g_totalExecutions = 0;
    g_coverageHits = 0;
}

__attribute__((noinline))
void FuzzCoverageRecord(uint64_t hits) {
    g_coverageHits = hits;
    g_totalExecutions++;
    
    if ((g_totalExecutions % 10000) == 0) {
        fprintf(stderr, "[coverage] runs=%llu coverage=%llu\n", 
            (unsigned long long)g_totalExecutions,
            (unsigned long long)g_coverageHits);
    }
}

__attribute__((noinline))
void FuzzCoverageFinal(void) {
    uint32_t elapsed = getElapsedTime();
    double rate = elapsed > 0 ? (double)g_totalExecutions / elapsed : 0;
    
    fprintf(stderr, "\n=== Coverage Results ===\n");
    fprintf(stderr, "Total executions:  %llu\n", (unsigned long long)g_totalExecutions);
    fprintf(stderr, "Unique coverage:   %llu\n", (unsigned long long)g_coverageHits);
    fprintf(stderr, "Elapsed time:      %us\n", elapsed);
    fprintf(stderr, "Executions/sec:    %.1f\n", rate);
    fprintf(stderr, "======================\n");
}

static uint32_t getElapsedTime(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec - g_startTime;
}

uint64_t FuzzCoverageGetHits(void) {
    return g_coverageHits;
}

uint64_t FuzzCoverageGetTotal(void) {
    return g_totalExecutions;
}