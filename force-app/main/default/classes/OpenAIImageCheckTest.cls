/**
 * Runs as the test user with the TypeSafe_User permission set added: the check reads files and
 * updates the case in user mode, and the admin can always see the case (SDO case automation can
 * move a new case out of its creator's sight).
 */
@IsTest
private class OpenAIImageCheckTest {
    private static final String PHOTO_SUBJECT = 'Photo case';
    private static final String NO_PHOTO_SUBJECT = 'No photo case';
    private static final Blob PNG_BYTES = Blob.valueOf('fake-png-bytes');

    @TestSetup
    static void setup() {
        TestDataFactory.grantTypeSafePermissionsToRunningUser();
        List<Case> cases = TestDataFactory.createCases(2, CaseTriageService.STATUS_ERROR, false);
        cases[0].Subject = PHOTO_SUBJECT;
        cases[1].Subject = NO_PHOTO_SUBJECT;
        TestDataFactory.prepareDemoOrgCaseAutomation();
        insert cases;
        TestDataFactory.createCaseFile(cases[0].Id, 'damage.png', PNG_BYTES);
    }

    private static Id caseId(String subject) {
        return [SELECT Id FROM Case WHERE Subject = :subject LIMIT 1].Id;
    }

    private static OpenAIImageCheck.Response checkCase(TypeSafeMock mock, Id targetCaseId) {
        TypeSafeConfig.cached = OpenAIDecisionsMock.openAIConfig();
        Test.setMock(HttpCalloutMock.class, mock);
        OpenAIImageCheck.Request request = new OpenAIImageCheck.Request();
        request.caseId = targetCaseId;
        Test.startTest();
        List<OpenAIImageCheck.Response> responses = OpenAIImageCheck.check(new List<OpenAIImageCheck.Request>{ request });
        Test.stopTest();
        return responses[0];
    }

    @IsTest
    static void shouldWriteDamageToCase_WhenPhotoShowsDamage() {
        Id photoCaseId = caseId(PHOTO_SUBJECT);

        OpenAIImageCheck.Response response = checkCase(new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.92, 2.1, 0.9)), photoCaseId);

        Case updated = [SELECT TS_Visible_Damage__c, TS_Damage_Severity__c FROM Case WHERE Id = :photoCaseId];
        Assert.isTrue(response.isSuccess, 'Check should succeed: ' + response.errorMessage);
        Assert.isFalse(response.needsReview, 'Confident damage should not need review');
        Assert.isTrue(response.caseUpdated, 'Case should be updated');
        Assert.areEqual(0.92, updated.TS_Visible_Damage__c, 'Damage probability should be written');
        Assert.areEqual(2.1, updated.TS_Damage_Severity__c, 'Severity should be written');
        Assert.areEqual('damage', [SELECT Outcome__c FROM TypeSafe_Log__c WHERE Id = :response.logId].Outcome__c, 'Log should record damage');
    }

    @IsTest
    static void shouldSendImageInline_WhenCheckingPhoto() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.92, 2.1, 0.9));

        OpenAIImageCheck.Response response = checkCase(mock, caseId(PHOTO_SUBJECT));

        String expectedDataUrl = OpenAIDecisionsClient.toDataUrl('image/png', PNG_BYTES);
        TypeSafe_Log__c log = [SELECT Context__c, Request__c FROM TypeSafe_Log__c WHERE Id = :response.logId];
        Assert.isTrue(mock.lastRequest.getBody().contains(expectedDataUrl), 'Image should be sent as an inline data URL');
        Assert.areEqual(OpenAIImageCheck.CONTEXT, log.Context__c, 'Log context should be Image_Check');
        Assert.isFalse(log.Request__c.contains(EncodingUtil.base64Encode(PNG_BYTES)), 'Image bytes should not be logged');
        Assert.areEqual('damage', response.fileName, 'Response should name the checked file');
    }

    @IsTest
    static void shouldNeedReview_WhenDamageInReviewBand() {
        OpenAIImageCheck.Response response = checkCase(
            new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.5, 1.0, 0.9)),
            caseId(PHOTO_SUBJECT)
        );

        Assert.isTrue(response.isSuccess, 'Check should succeed');
        Assert.isTrue(response.needsReview, 'Damage between the review and action thresholds should need review');
    }

    @IsTest
    static void shouldNeedReview_WhenSeverityConfidenceLow() {
        OpenAIImageCheck.Response response = checkCase(
            new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.05, 0.4, 0.3)),
            caseId(PHOTO_SUBJECT)
        );

        Assert.isTrue(response.needsReview, 'Low severity confidence should need review');
    }

    @IsTest
    static void shouldFailWithoutCallout_WhenCaseHasNoImage() {
        TypeSafeMock mock = new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.9, 2, 0.9));

        OpenAIImageCheck.Response response = checkCase(mock, caseId(NO_PHOTO_SUBJECT));

        Assert.isFalse(response.isSuccess, 'Check should fail');
        Assert.areEqual('NO_IMAGE', response.errorType, 'Error type should be NO_IMAGE');
        Assert.areEqual(0, mock.callCount, 'No callout should be made');
    }

    @IsTest
    static void shouldFailValidation_WhenCaseIdMissing() {
        OpenAIImageCheck.Response response = checkCase(new TypeSafeMock(200, '{}'), null);

        Assert.areEqual('VALIDATION', response.errorType, 'A missing case Id should fail validation');
        Assert.isTrue(response.needsReview, 'A failed check should ask for review');
    }

    @IsTest
    static void shouldFail_WhenModelRefuses() {
        String body = OpenAIDecisionsMock.envelope(
            new List<Object>{
                OpenAIDecisionsMock.refusal('visible_damage'),
                OpenAIDecisionsMock.score('damage_severity', 1, 0.9)
            }
        );

        OpenAIImageCheck.Response response = checkCase(new TypeSafeMock(200, body), caseId(PHOTO_SUBJECT));

        Assert.isFalse(response.isSuccess, 'A refusal should fail the check');
        Assert.isFalse(response.caseUpdated, 'Case should not be updated');
        Assert.isTrue(response.errorMessage.contains('refused'), 'Error should mention the refusal');
    }

    @IsTest
    static void shouldFailAndLog_WhenApiErrors() {
        OpenAIImageCheck.Response response = checkCase(new TypeSafeMock(500, '{"error":{"message":"server"}}'), caseId(PHOTO_SUBJECT));

        Assert.areEqual('OPENAI_ERROR', response.errorType, 'Error type should be OPENAI_ERROR');
        Assert.isNotNull(response.logId, 'The failed call should still be logged');
    }

    @IsTest
    static void shouldReturnOneResponsePerRequest_WhenSameCaseAskedTwice() {
        TypeSafeConfig.cached = OpenAIDecisionsMock.openAIConfig();
        Test.setMock(HttpCalloutMock.class, new TypeSafeMock(200, OpenAIDecisionsMock.imageCheck(0.92, 2.1, 0.9)));
        OpenAIImageCheck.Request request = new OpenAIImageCheck.Request();
        request.caseId = caseId(PHOTO_SUBJECT);

        Test.startTest();
        List<OpenAIImageCheck.Response> responses = OpenAIImageCheck.check(new List<OpenAIImageCheck.Request>{ request, request });
        Test.stopTest();

        Assert.areEqual(2, responses.size(), 'Each request should get a response');
        Assert.isTrue(responses[0].caseUpdated, 'The first request should update the case');
        Assert.isFalse(responses[1].caseUpdated, 'A duplicate case should be written only once');
    }
}
