@IsTest
private class TypeSafeClientTest {
    private static final String CONTEXT = 'Case_Triage';

    private static TypeSafeResult askTriage(TypeSafeMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        TypeSafeClient client = new TypeSafeClient(new TypeSafeConfig());
        return client.ask('Help!', CaseTriageService.buildQuestions(), CONTEXT, null);
    }

    @IsTest
    static void shouldParseAllAnswerTypes_WhenResponseIs200() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());

        Test.startTest();
        TypeSafeResult result = askTriage(mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Call should succeed');
        Assert.areEqual(TypeSafeMock.MODEL, result.model, 'Model should be parsed');
        Assert.areEqual(312, result.inputTokens, 'Input tokens should be parsed');
        Assert.areEqual('Facilities', result.getAnswer('department').choice, 'Choice should be parsed');
        Assert.areEqual(0.85, result.getAnswer('department').probabilities.get('Facilities'), 'Choice probabilities should be parsed');
        Assert.areEqual(0.9, result.getAnswer('urgency').noul, 'Noul should be parsed');
        Assert.isNull(result.getAnswer('urgency').confidence, 'Noul answers carry no confidence');
        Assert.areEqual(1.2, result.getAnswer('frustration').score, 'Score should be parsed');
        Assert.areEqual('L3', result.getAnswer('frustration').legend.get('3'), 'Score legend should be parsed');
    }

    @IsTest
    static void shouldSendModelAndQuestions_WhenAsking() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());

        Test.startTest();
        askTriage(mock);
        Test.stopTest();

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Map<String, Object> questions = (Map<String, Object>) sent.get('questions');
        Assert.areEqual(TypeSafeClient.ENDPOINT, mock.lastRequest.getEndpoint(), 'Should call the Named Credential endpoint');
        Assert.areEqual('POST', mock.lastRequest.getMethod(), 'Should POST');
        Assert.areEqual('jev-latest', sent.get('model'), 'Should send the configured model');
        Assert.areEqual(5, questions.size(), 'Should send all five triage questions in one request');
    }

    @IsTest
    static void shouldBuildSuccessLog_WhenResponseIs200() {
        TypeSafeMock mock = new TypeSafeMock(200, TypeSafeMock.confidentTriage());

        Test.startTest();
        TypeSafeResult result = askTriage(mock);
        Test.stopTest();

        Assert.isNull(result.log.Id, 'Log should not be saved by the client');
        Assert.isTrue(result.log.Success__c, 'Log should record success');
        Assert.areEqual(200, result.log.Status_Code__c, 'Log should record the status code');
        Assert.areEqual(CONTEXT, result.log.Context__c, 'Log should record the context');
        Assert.areEqual(TypeSafeMock.MODEL, result.log.Model__c, 'Log should record the model');
        Assert.isNotNull(result.log.Request__c, 'Log should keep the request body');
    }

    @IsTest
    static void shouldReportError_WhenResponseIs422() {
        TypeSafeMock mock = new TypeSafeMock(422, '{"detail":"questions.urgency.type is required"}');

        Test.startTest();
        TypeSafeResult result = askTriage(mock);
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isFalse(result.isRetryable(), 'A validation error should not be retried');
        Assert.isTrue(result.errorMessage.startsWith('HTTP 422'), 'Error should carry the status');
        Assert.isFalse(result.log.Success__c, 'Log should record failure');
    }

    @IsTest
    static void shouldBeRetryable_WhenResponseIs429() {
        TypeSafeMock mock = new TypeSafeMock(429, '{"detail":"rate limited"}');

        Test.startTest();
        TypeSafeResult result = askTriage(mock);
        Test.stopTest();

        Assert.isTrue(result.isRetryable(), 'A rate limit should be retryable');
    }

    @IsTest
    static void shouldReportError_WhenCalloutThrows() {
        Test.startTest();
        TypeSafeResult result = askTriage(TypeSafeMock.failing());
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.startsWith('Callout failed'), 'Error should describe the callout failure');
        Assert.isNotNull(result.log, 'A log should still be built');
    }

    @IsTest
    static void shouldReportError_WhenBodyIsNotJson() {
        Test.startTest();
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '<html>gateway</html>'));
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('not valid JSON'), 'Error should describe the parse failure');
    }

    @IsTest
    static void shouldReportError_WhenAnswersMissing() {
        Test.startTest();
        TypeSafeResult result = askTriage(new TypeSafeMock(200, '{"model":"jev-1.13.0"}'));
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('no answers'), 'Error should describe the missing answers');
    }

    @IsTest
    static void shouldReportError_WhenAnswerHasNoType() {
        String body = '{"model":"jev-1.13.0","answers":{"urgency":{"noul":0.5}}}';

        Test.startTest();
        TypeSafeResult result = askTriage(new TypeSafeMock(200, body));
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Call should fail');
        Assert.isTrue(result.errorMessage.contains('missing its type'), 'Error should describe the bad answer');
    }

    @IsTest
    static void shouldThrow_WhenStateIsNull() {
        TypeSafeClient client = new TypeSafeClient(new TypeSafeConfig());
        try {
            client.ask(null, CaseTriageService.buildQuestions(), CONTEXT, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('state'), 'Message should mention state');
        }
    }

    @IsTest
    static void shouldThrow_WhenQuestionsEmpty() {
        TypeSafeClient client = new TypeSafeClient(null);
        try {
            client.ask('Help!', new Map<String, Object>(), CONTEXT, null);
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('question'), 'Message should mention questions');
        }
    }

    @IsTest
    static void shouldThrow_WhenAnswerKeyMissing() {
        TypeSafeResult result = new TypeSafeResult();
        try {
            result.getAnswer('nope');
            Assert.fail('Expected TypeSafeException');
        } catch (TypeSafeException e) {
            Assert.isTrue(e.getMessage().contains('nope'), 'Message should name the missing question');
        }
    }
}
