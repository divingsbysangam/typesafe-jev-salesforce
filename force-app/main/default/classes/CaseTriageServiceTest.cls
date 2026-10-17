@IsTest
private class CaseTriageServiceTest {
    @TestSetup
    static void setup() {
        User typeSafeUser = TestDataFactory.createTypeSafeUser();
        System.runAs(typeSafeUser) {
            // Error status keeps the trigger from queueing triage during setup.
            TestDataFactory.createCases(1, CaseTriageService.STATUS_ERROR, true);
        }
    }

    private static Case triageWith(TypeSafeMock mock, Boolean allowRetry) {
        Test.setMock(HttpCalloutMock.class, mock);
        // Queried as the test runner: SDO case automation can hide the case from its creator.
        Case target = [SELECT Id FROM Case LIMIT 1];
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            CaseTriageService.triage(new Set<Id>{ target.Id }, allowRetry);
            Test.stopTest();
        }
        return reload(target.Id);
    }

    private static Id queueId(String developerName) {
        return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :developerName LIMIT 1].Id;
    }

    private static Case reload(Id caseId) {
        return [
            SELECT
                Id, Priority, OwnerId, TS_Department__c, TS_Department_Confidence__c, TS_Urgency__c,
                TS_Refund_Requested__c, TS_Frustration__c, TS_Churn_Risk__c, TS_Model__c,
                TS_Triage_Status__c, TS_Triage_Reason__c
            FROM Case
            WHERE Id = :caseId
        ];
    }

    @IsTest
    static void shouldAutoRoute_WhenAllAnswersConfident() {
        Case triaged = triageWith(new TypeSafeMock(200, TypeSafeMock.confidentTriage()), true);

        Assert.areEqual(CaseTriageService.STATUS_AUTO_ROUTED, triaged.TS_Triage_Status__c, 'Case should auto-route');
        Assert.areEqual('Facilities', triaged.TS_Department__c, 'Department should be written');
        Assert.areEqual(0.9, triaged.TS_Urgency__c, 'Urgency probability should be written');
        Assert.areEqual(TypeSafeMock.MODEL, triaged.TS_Model__c, 'Model should be written');
        Assert.areEqual('High', triaged.Priority, 'Urgency 0.9 should make the case High priority');
    }

    @IsTest
    static void shouldSaveOneLog_WhenCaseTriaged() {
        Case triaged = triageWith(new TypeSafeMock(200, TypeSafeMock.confidentTriage()), true);

        TypeSafe_Log__c log = [SELECT Context__c, Record_Id__c, Outcome__c FROM TypeSafe_Log__c];
        Assert.areEqual(CaseTriageService.CONTEXT, log.Context__c, 'Log context should be Case_Triage');
        Assert.areEqual(String.valueOf(triaged.Id), log.Record_Id__c, 'Log should point at the case');
        Assert.areEqual(CaseTriageService.STATUS_AUTO_ROUTED, log.Outcome__c, 'Log outcome should match the decision');
    }

    @IsTest
    static void shouldNeedReview_WhenDepartmentUncertain() {
        String body = TypeSafeMock.triage('Billing', 0.5, 0.1, 0.1, 0.5, 0.9, 0.2, 0.9);

        Case triaged = triageWith(new TypeSafeMock(200, body), true);

        Assert.areEqual(CaseTriageService.STATUS_NEEDS_REVIEW, triaged.TS_Triage_Status__c, 'Case should need review');
        Assert.isTrue(triaged.TS_Triage_Reason__c.contains('department confidence 0.50'), 'Reason should name the uncertain answer');
    }

    @IsTest
    static void shouldNeedReview_WhenRefundRoutedOutsideBilling() {
        String body = TypeSafeMock.triage('Facilities', 0.9, 0.1, 0.9, 0.5, 0.9, 0.2, 0.9);

        Case triaged = triageWith(new TypeSafeMock(200, body), true);

        Assert.areEqual(CaseTriageService.STATUS_NEEDS_REVIEW, triaged.TS_Triage_Status__c, 'Case should need review');
        Assert.isTrue(triaged.TS_Triage_Reason__c.contains('refund requested but routed to Facilities'), 'Reason should name the conflict');
    }

    @IsTest
    static void shouldMarkError_WhenApiFails() {
        Case triaged = triageWith(new TypeSafeMock(500, 'boom'), true);

        Assert.areEqual(CaseTriageService.STATUS_ERROR, triaged.TS_Triage_Status__c, 'Case should be marked Error');
        Assert.isTrue(triaged.TS_Triage_Reason__c.startsWith('HTTP 500'), 'Reason should carry the HTTP error');
    }

    @IsTest
    static void shouldMarkError_WhenAnswerMissing() {
        String body = TypeSafeMock.envelope(new Map<String, Object>{ 'urgency' => TypeSafeMock.noul(0.2) });

        Case triaged = triageWith(new TypeSafeMock(200, body), true);

        Assert.areEqual(CaseTriageService.STATUS_ERROR, triaged.TS_Triage_Status__c, 'Case should be marked Error');
        Assert.isTrue(triaged.TS_Triage_Reason__c.contains('department'), 'Reason should name the missing answer');
    }

    @IsTest
    static void shouldReturnRetryId_WhenRateLimitedAndRetryAllowed() {
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(429, '{}'));
        Set<Id> retryIds;
        Case target = [SELECT Id FROM Case LIMIT 1];
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            retryIds = CaseTriageService.triage(new Set<Id>{ target.Id }, true);
            Test.stopTest();
        }

        Assert.isTrue(retryIds.contains(target.Id), 'Rate-limited case should be returned for retry');
        Assert.areEqual(CaseTriageService.STATUS_ERROR, reload(target.Id).TS_Triage_Status__c, 'Case should be left untouched');
        Assert.areEqual('retry_scheduled', [SELECT Outcome__c FROM TypeSafe_Log__c].Outcome__c, 'Log should record the retry');
    }

    @IsTest
    static void shouldMarkError_WhenRateLimitedAndRetryNotAllowed() {
        Case triaged = triageWith(new TypeSafeMock(429, '{}'), false);

        Assert.isTrue(triaged.TS_Triage_Reason__c.startsWith('HTTP 429'), 'Final attempt should record the rate limit');
    }

    @IsTest
    static void shouldReturnEmpty_WhenNoCaseIds() {
        Set<Id> retryIds = CaseTriageService.triage(new Set<Id>(), true);

        Assert.isTrue(retryIds.isEmpty(), 'Nothing to retry for no input');
    }

    @IsTest
    static void shouldReturnMedium_WhenOnlyMildSignals() {
        String priority = CaseTriageService.derivePriority(0.4, 0.5, 0.2, new TypeSafeConfig());

        Assert.areEqual('Medium', priority, 'Urgency above the review threshold should be Medium');
    }

    @IsTest
    static void shouldReturnLow_WhenNoSignals() {
        String priority = CaseTriageService.derivePriority(0.1, 0.2, 0.1, new TypeSafeConfig());

        Assert.areEqual('Low', priority, 'No signal should be Low');
    }

    @IsTest
    static void shouldReturnHigh_WhenChurnHigh() {
        String priority = CaseTriageService.derivePriority(0.1, 0.2, 2.4, new TypeSafeConfig());

        Assert.areEqual('High', priority, 'Churn at level 2 or above should be High');
    }

    @IsTest
    static void shouldAssignDepartmentQueue_WhenAutoRouted() {
        Case triaged = triageWith(new TypeSafeMock(200, TypeSafeMock.confidentTriage()), true);

        Assert.areEqual(queueId('TS_Facilities'), triaged.OwnerId, 'TypeSafe_Case_Routing flow should assign the department queue');
    }

    @IsTest
    static void shouldAssignReviewQueue_WhenNeedsReview() {
        String body = TypeSafeMock.triage('Billing', 0.5, 0.1, 0.1, 0.5, 0.9, 0.2, 0.9);

        Case triaged = triageWith(new TypeSafeMock(200, body), true);

        Assert.areEqual(queueId('TS_Review'), triaged.OwnerId, 'TypeSafe_Case_Routing flow should assign the review queue');
    }
}
