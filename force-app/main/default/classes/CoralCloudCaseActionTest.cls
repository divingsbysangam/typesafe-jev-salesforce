@IsTest
private class CoralCloudCaseActionTest {
    private static final Integer BULK_COUNT = 251;

    @TestSetup
    static void setup() {
        TestDataFactory.createTypeSafeUser();
        // Separate transaction context: the user/permission set inserts above are setup DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory.prepareDemoOrgCaseAutomation();
        }
    }

    private static CoralCloudCaseAction.Request request(String subject, String description, String email) {
        CoralCloudCaseAction.Request request = new CoralCloudCaseAction.Request();
        request.subject = subject;
        request.description = description;
        request.guestEmail = email;
        return request;
    }

    private static List<CoralCloudCaseAction.Response> runAsAgent(List<CoralCloudCaseAction.Request> requests) {
        // Mock Jev so the triage job queued by the Case trigger can run.
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, TypeSafeMock.confidentTriage()));
        List<CoralCloudCaseAction.Response> responses;
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            responses = CoralCloudCaseAction.createCases(requests);
            Test.stopTest();
        }
        return responses;
    }

    @IsTest
    static void shouldCreateCaseAndReturnNumber_WhenValidRequest() {
        List<CoralCloudCaseAction.Response> responses = runAsAgent(
            new List<CoralCloudCaseAction.Request>{ request('Room AC broken', 'The AC in room 204 stopped working.', 'guest@example.com') }
        );

        Case created = [SELECT CaseNumber, Subject, Origin, SuppliedEmail FROM Case WHERE Id = :responses[0].caseId];
        Assert.isTrue(responses[0].isSuccess, 'Case should be created');
        Assert.areEqual(created.CaseNumber, responses[0].caseNumber, 'Case number should be returned');
        Assert.areEqual(CoralCloudCaseAction.ORIGIN, created.Origin, 'Origin should mark the agent as the source');
        Assert.areEqual('guest@example.com', created.SuppliedEmail, 'Guest email should be stored');
    }

    @IsTest
    static void shouldQueueJevTriage_WhenCaseCreated() {
        List<CoralCloudCaseAction.Response> responses = runAsAgent(
            new List<CoralCloudCaseAction.Request>{ request('Room AC broken', 'The AC in room 204 stopped working.', null) }
        );

        Case created = [SELECT TS_Triage_Status__c FROM Case WHERE Id = :responses[0].caseId];
        Assert.areEqual(CaseTriageService.STATUS_AUTO_ROUTED, created.TS_Triage_Status__c, 'Agent-filed cases should be triaged by Jev');
    }

    @IsTest
    static void shouldReturnValidationError_WhenDescriptionBlank() {
        List<CoralCloudCaseAction.Response> responses = runAsAgent(
            new List<CoralCloudCaseAction.Request>{ request('Room AC broken', ' ', null) }
        );

        Assert.isFalse(responses[0].isSuccess, 'Blank description should fail');
        Assert.areEqual('VALIDATION', responses[0].errorType, 'Error type should be VALIDATION');
        Assert.areEqual(0, [SELECT COUNT() FROM Case], 'No case should be created');
    }

    @IsTest
    static void shouldKeepOrder_WhenMixedValidAndInvalid() {
        List<CoralCloudCaseAction.Response> responses = runAsAgent(
            new List<CoralCloudCaseAction.Request>{
                request('Late checkout', 'Can I check out at 2pm?', null),
                request('', 'No subject', null),
                request('Spa booking', 'Please book a massage.', null)
            }
        );

        Assert.isTrue(responses[0].isSuccess, 'First request should succeed');
        Assert.isFalse(responses[1].isSuccess, 'Second request should fail validation');
        Assert.isTrue(responses[2].isSuccess, 'Third request should succeed');
        Assert.areEqual(2, [SELECT COUNT() FROM Case], 'Only valid requests create cases');
    }

    @IsTest
    static void shouldCreateAllCases_WhenBulk() {
        List<CoralCloudCaseAction.Request> requests = new List<CoralCloudCaseAction.Request>();
        for (Integer i = 0; i < BULK_COUNT; i++) {
            requests.add(request('Issue ' + i, 'Guest issue number ' + i, null));
        }

        List<CoralCloudCaseAction.Response> responses = runAsAgent(requests);

        Assert.areEqual(BULK_COUNT, responses.size(), 'One response per request');
        Assert.areEqual(BULK_COUNT, [SELECT COUNT() FROM Case WHERE Origin = :CoralCloudCaseAction.ORIGIN], 'Every case should be created');
    }

    @IsTest
    static void shouldReturnEmpty_WhenNoRequests() {
        List<CoralCloudCaseAction.Response> responses = CoralCloudCaseAction.createCases(null);

        Assert.isTrue(responses.isEmpty(), 'No requests should give no responses');
    }
}
