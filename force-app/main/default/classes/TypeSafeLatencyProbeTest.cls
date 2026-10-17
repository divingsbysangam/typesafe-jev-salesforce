@IsTest
private class TypeSafeLatencyProbeTest {
    private static final Integer CALLS = 5;

    @TestSetup
    static void setup() {
        TestDataFactory.createTypeSafeUser();
    }

    private static TypeSafeLatencyProbe.Summary runProbe(TypeSafeMock mock, Integer calls) {
        Test.setMock(HttpCalloutMock.class, mock);
        TypeSafeLatencyProbe.Summary summary;
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            summary = TypeSafeLatencyProbe.run(calls);
            Test.stopTest();
        }
        return summary;
    }

    private static String probeBody() {
        return TypeSafeMock.envelope(
            new Map<String, Object>{
                'is_urgent' => TypeSafeMock.noul(0.9),
                'department' => TypeSafeMock.choice('technical', 0.8),
                'frustration' => TypeSafeMock.score(1.6, 0.78)
            }
        );
    }

    @IsTest
    static void shouldSummarizeAndLog_WhenAllCallsSucceed() {
        TypeSafeLatencyProbe.Summary summary = runProbe(new TypeSafeMock(200, probeBody()), CALLS);

        Assert.areEqual(CALLS, summary.calls, 'All calls should run');
        Assert.areEqual(CALLS, summary.successes, 'All calls should succeed');
        Assert.isNotNull(summary.coldMs, 'Cold call latency should be recorded');
        Assert.isNotNull(summary.p50Ms, 'Warm p50 should be computed');
        Assert.areEqual(TypeSafeMock.MODEL, summary.model, 'Model should be recorded');
        Assert.areEqual(CALLS, [SELECT COUNT() FROM TypeSafe_Log__c WHERE Context__c = :TypeSafeLatencyProbe.CONTEXT], 'Every call should be logged');
    }

    @IsTest
    static void shouldCapCalls_WhenAboveMaximum() {
        TypeSafeLatencyProbe.Summary summary = runProbe(new TypeSafeMock(200, probeBody()), 500);

        Assert.areEqual(TypeSafeLatencyProbe.MAX_CALLS, summary.calls, 'Calls should be capped');
    }

    @IsTest
    static void shouldRecordLastError_WhenCallsFail() {
        TypeSafeLatencyProbe.Summary summary = runProbe(new TypeSafeMock(401, '{"detail":"bad key"}'), 2);

        Assert.areEqual(0, summary.successes, 'No call should succeed');
        Assert.isTrue(summary.lastError.startsWith('HTTP 401'), 'Last error should be kept');
        Assert.isTrue(summary.toText().contains('last error'), 'Summary text should include the error');
    }

    @IsTest
    static void shouldComputePercentiles_WhenLatenciesKnown() {
        TypeSafeLatencyProbe.Summary summary = new TypeSafeLatencyProbe.Summary();
        List<Long> latencies = new List<Long>{ 100, 20, 90, 30, 80, 40, 70, 50, 60, 10 };

        summary.setWarmStats(latencies);

        Assert.areEqual(10, summary.minMs, 'Min should be the smallest value');
        Assert.areEqual(100, summary.maxMs, 'Max should be the largest value');
        Assert.areEqual(50, summary.p50Ms, 'p50 of 10..100 should be 50 (nearest rank)');
        Assert.areEqual(100, summary.p95Ms, 'p95 of 10..100 should be 100 (nearest rank)');
    }
}
