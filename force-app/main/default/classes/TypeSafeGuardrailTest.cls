@IsTest
private class TypeSafeGuardrailTest {
    private static final Integer BULK_COUNT = 60;

    @TestSetup
    static void setup() {
        TestDataFactory.createTypeSafeUser();
    }

    private static TypeSafeGuardrail.Request request(String text, String side) {
        TypeSafeGuardrail.Request request = new TypeSafeGuardrail.Request();
        request.text = text;
        request.side = side;
        return request;
    }

    private static TypeSafeGuardrail.Response screenOne(TypeSafeMock mock, String side) {
        Test.setMock(HttpCalloutMock.class, mock);
        List<TypeSafeGuardrail.Response> responses;
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            responses = TypeSafeGuardrail.screen(new List<TypeSafeGuardrail.Request>{ request('Some message', side) });
            Test.stopTest();
        }
        return responses[0];
    }

    @IsTest
    static void shouldPass_WhenNoHazardFires() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.05, 0.05, 0.01, 0.1)), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_PASS, response.action, 'A clean message should pass');
        Assert.isTrue(response.isSuccess, 'Check should succeed');
        Assert.areEqual(TypeSafeMock.MODEL, response.model, 'Model should be returned');
    }

    @IsTest
    static void shouldBlock_WhenJailbreakAboveActionThreshold() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, TypeSafeMock.guardrail(0.95, 0.1, 0.05, 0.01, 1.0)), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_BLOCK, response.action, 'A jailbreak should be blocked');
        Assert.areEqual(0.95, response.policyRisk, 'Policy risk should carry the jailbreak probability');
        Assert.isTrue(response.reason.contains('jailbreak 0.95'), 'Reason should name the hazard');
    }

    @IsTest
    static void shouldReview_WhenCustomerSharesPii() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.05, 0.9, 0.01, 0.5)), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_REVIEW, response.action, 'PII on the way in should go to review, not block');
    }

    @IsTest
    static void shouldBlock_WhenReplyLeaksPii() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.05, 0.9, 0.01, 0.5));

        TypeSafeGuardrail.Response response = screenOne(mock, 'output');

        Assert.areEqual(TypeSafeGuardrail.ACTION_BLOCK, response.action, 'PII on the way out should be blocked');
        Assert.isTrue(mock.lastRequest.getBody().contains('pii_leak'), 'Output side should send the output battery');
    }

    @IsTest
    static void shouldRouteToSupport_WhenSelfHarmAndJailbreakBothFire() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, TypeSafeMock.guardrail(0.9, 0.1, 0.05, 0.9, 1.0)), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_SUPPORT, response.action, 'Support should take precedence over block');
    }

    @IsTest
    static void shouldEscalateToBlock_WhenReviewAndSeverityHigh() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.5, 0.05, 0.01, 2.5)), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_BLOCK, response.action, 'High severity should escalate review to block');
        Assert.isTrue(response.reason.contains('escalated'), 'Reason should explain the escalation');
    }

    @IsTest
    static void shouldFailClosedAndLog_WhenApiErrors() {
        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(529, 'overloaded'), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_REVIEW, response.action, 'An unavailable guardrail should fail closed to review');
        Assert.isFalse(response.isSuccess, 'Check should report failure');
        Assert.isNotNull(response.logId, 'The failed call should still be logged');
    }

    @IsTest
    static void shouldFailClosed_WhenAnswerMissing() {
        String body = TypeSafeMock.envelope(new Map<String, Object>{ 'jailbreak' => TypeSafeMock.noul(0.1) });

        TypeSafeGuardrail.Response response = screenOne(new TypeSafeMock(200, body), 'input');

        Assert.areEqual(TypeSafeGuardrail.ACTION_REVIEW, response.action, 'An incomplete answer set should fail closed');
    }

    @IsTest
    static void shouldFailClosedWithoutCallout_WhenTextBlank() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.05, 0.05, 0.01, 0.1));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<TypeSafeGuardrail.Response> responses = TypeSafeGuardrail.screen(new List<TypeSafeGuardrail.Request>{ request(' ', 'input') });
        Test.stopTest();

        Assert.areEqual(TypeSafeGuardrail.ACTION_REVIEW, responses[0].action, 'Blank text should fail closed');
        Assert.areEqual('VALIDATION', responses[0].errorType, 'Error type should be VALIDATION');
        Assert.areEqual(0, mock.callCount, 'No callout for blank text');
    }

    @IsTest
    static void shouldScreenAndLogEveryRequest_WhenBulk() {
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, TypeSafeMock.guardrail(0.05, 0.05, 0.05, 0.01, 0.1)));
        List<TypeSafeGuardrail.Request> requests = new List<TypeSafeGuardrail.Request>();
        for (Integer i = 0; i < BULK_COUNT; i++) {
            requests.add(request('Message ' + i, 'input'));
        }

        List<TypeSafeGuardrail.Response> responses;
        System.runAs(TestDataFactory.getTypeSafeUser()) {
            Test.startTest();
            responses = TypeSafeGuardrail.screen(requests);
            Test.stopTest();
        }

        Assert.areEqual(BULK_COUNT, responses.size(), 'One response per request');
        Assert.areEqual(BULK_COUNT, [SELECT COUNT() FROM TypeSafe_Log__c WHERE Context__c = 'Guardrail_Input'], 'One log per request');
    }

    @IsTest
    static void shouldReview_WhenProbabilityBetweenThresholds() {
        List<String> reasons = new List<String>();

        String action = TypeSafeGuardrail.route(new Map<String, Decimal>{ 'harmful_request' => 0.5 }, 0.5, new TypeSafeConfig(), reasons);

        Assert.areEqual(TypeSafeGuardrail.ACTION_REVIEW, action, 'Between review and action thresholds should review');
        Assert.areEqual(1, reasons.size(), 'One reason should be recorded');
    }
}
