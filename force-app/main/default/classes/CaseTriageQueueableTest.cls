/**
 * Covers CaseTrigger, CaseTriggerHandler and CaseTriageQueueable end to end.
 */
@IsTest
private class CaseTriageQueueableTest {
    private static final Integer BULK_COUNT = 251;
    private static final Integer TRIGGER_CHUNK = 200;

    @TestSetup
    static void setup() {
        TestDataFactory.createTypeSafeUser();
    }

    private static List<Case> selectCasesByStatus(String status) {
        return [SELECT Id FROM Case WHERE TS_Triage_Status__c = :status];
    }

    @IsTest
    static void shouldTriageCase_WhenInserted() {
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, TypeSafeMock.confidentTriage()));

        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            TestDataFactory.createCases(1, null, true);
            Test.stopTest();
        }

        Assert.areEqual(1, selectCasesByStatus(CaseTriageService.STATUS_AUTO_ROUTED).size(), 'New case should be triaged');
    }

    @IsTest
    static void shouldTriageFirstBatch_WhenBulkInserted() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            TestDataFactory.createCases(BULK_COUNT, null, true);
            Test.stopTest();
        }

        // 251 inserts fire the trigger twice (200 + 51); each chunk queues one job, and each job
        // handles BATCH_SIZE cases before chaining (chained jobs don't run in tests).
        Integer batchSize = CaseTriageQueueable.BATCH_SIZE;
        Integer expectedTriaged = Math.min(TRIGGER_CHUNK, batchSize) + Math.min(BULK_COUNT - TRIGGER_CHUNK, batchSize);
        Assert.areEqual(expectedTriaged, mock.callCount, 'One callout per case in each first batch');
        Assert.areEqual(expectedTriaged, selectCasesByStatus(CaseTriageService.STATUS_AUTO_ROUTED).size(), 'First batches should be triaged');
        Assert.areEqual(BULK_COUNT - expectedTriaged, selectCasesByStatus(CaseTriageService.STATUS_PENDING).size(), 'The rest should wait for the chained jobs');
    }

    @IsTest
    static void shouldRetriage_WhenStatusSetToPending() {
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, TypeSafeMock.confidentTriage()));

        Case existing;
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            existing = TestDataFactory.createCases(1, CaseTriageService.STATUS_ERROR, true)[0];
        }
        // An agent (the test runner) resets the status; SDO automation may hide the case from its creator.
        Test.startTest();
        update new Case(Id = existing.Id, TS_Triage_Status__c = CaseTriageService.STATUS_PENDING);
        Test.stopTest();

        Assert.areEqual(1, selectCasesByStatus(CaseTriageService.STATUS_AUTO_ROUTED).size(), 'Setting Pending should re-run triage');
    }

    @IsTest
    static void shouldSkipTriage_WhenCaseHasNoText() {
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            TestDataFactory.prepareDemoOrgCaseAutomation();
            Test.startTest();
            insert new Case(Origin = 'Email');
            Test.stopTest();
        }

        Case inserted = [SELECT TS_Triage_Status__c FROM Case LIMIT 1];
        Assert.isNull(inserted.TS_Triage_Status__c, 'A case with no subject or description should not be triaged');
        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'CaseTriageQueueable'], 'No job should be queued');
    }

    @IsTest
    static void shouldMarkError_WhenChainDepthLimitReached() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());
        Test.setMock(HttpCalloutMock.class, mock);
        Integer overflow = 1;

        System.runAs(TestDataFactory.getTypeSafeUser()) {
            List<Case> cases = TestDataFactory.createCases(CaseTriageQueueable.BATCH_SIZE + overflow, CaseTriageService.STATUS_ERROR, true);
            List<Id> caseIds = new List<Id>(new Map<Id, Case>(cases).keySet());
            Test.startTest();
            System.enqueueJob(new CaseTriageQueueable(caseIds, 1, 20));
            Test.stopTest();
        }

        List<Case> stopped = [SELECT Id FROM Case WHERE TS_Triage_Reason__c LIKE '%chain depth%'];
        Assert.areEqual(overflow, stopped.size(), 'Cases beyond the depth limit should be marked Error');
    }

    @IsTest
    static void shouldDoNothing_WhenNoCaseIds() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new CaseTriageQueueable(new List<Id>()));
        Test.stopTest();

        Assert.areEqual(0, mock.callCount, 'No callouts for an empty job');
    }
}
