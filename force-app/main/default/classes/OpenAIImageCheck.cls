/**
 * Checks the newest photo attached to a case for visible damage with OpenAI Decisions, which
 * takes images as well as text (Jev is text-only, so this action always uses an OpenAI profile:
 * the active one if it is OpenAI, otherwise the "OpenAI" TypeSafe_Setting__mdt record).
 *
 * One request asks two questions about the image: a predicate (is damage visible?) and a score
 * (how serious?). The answers are written to TS_Visible_Damage__c / TS_Damage_Severity__c, and
 * the thresholds from the profile decide whether a human should look.
 *
 * Images are read from Salesforce Files in user mode and sent inline as base64 (the API does not
 * fetch URLs). To stay inside the heap and callout-size limits, each image must be at most
 * MAX_IMAGE_BYTES and one transaction loads at most MAX_TOTAL_BYTES; the rest return an error
 * and can be retried in a later transaction.
 */
public with sharing class OpenAIImageCheck {
    public static final String CONTEXT = 'Image_Check';
    @TestVisible
    private static final String Q_DAMAGE = 'visible_damage';
    @TestVisible
    private static final String Q_SEVERITY = 'damage_severity';
    @TestVisible
    private static final Integer MAX_IMAGE_BYTES = 2000000;
    @TestVisible
    private static final Integer MAX_TOTAL_BYTES = 3000000;
    private static final String PROMPT_TEXT = 'Photo a guest attached to a Coral Cloud Resorts support case.';
    private static final Map<String, String> MIME_BY_FILE_TYPE = new Map<String, String>{
        'PNG' => 'image/png',
        'JPG' => 'image/jpeg',
        'JPEG' => 'image/jpeg',
        'GIF' => 'image/gif',
        'WEBP' => 'image/webp'
    };

    /**
     * Checks one case photo per request. All callouts run before any DML.
     * @param requests Cases to check.
     * @return One response per request, in order.
     */
    @InvocableMethod(
        label='OpenAI: Check Case Photo for Damage'
        description='Asks OpenAI Decisions whether the newest image attached to the case shows visible damage, and how serious it is. Writes TS Visible Damage and TS Damage Severity on the case.'
        category='TypeSafe'
        callout=true
    )
    public static List<Response> check(List<Request> requests) {
        List<Request> safeRequests = requests ?? new List<Request>();
        Set<Id> caseIds = new Set<Id>();
        for (Request request : safeRequests) {
            if (request?.caseId != null) {
                caseIds.add(request.caseId);
            }
        }
        Map<Id, ContentDocumentLink> imageByCaseId = CaseImageSelector.selectLatestImageByCaseId(
            caseIds,
            MIME_BY_FILE_TYPE.keySet()
        );
        Map<Id, ContentVersion> versionsById = CaseImageSelector.selectVersionData(
            pickWithinBudget(imageByCaseId.values())
        );

        List<Response> responses = new List<Response>();
        TypeSafeConfig config;
        try {
            config = openAIConfig();
        } catch (TypeSafeException e) {
            for (Request request : safeRequests) {
                responses.add(fail(new Response(), e.getMessage(), 'CONFIG'));
            }
            return responses;
        }
        Checker checker = new Checker(new OpenAIDecisionsClient(config), config, imageByCaseId, versionsById);
        for (Request request : safeRequests) {
            responses.add(checker.checkOne(request));
        }
        persist(safeRequests, responses);
        return responses;
    }

    /**
     * Two questions in one request: the predicate mirrors OpenAI's damage example; the score
     * levels follow the "Label: description" convention TypeSafeQuestions uses.
     * @return Question id to question map.
     */
    @TestVisible
    private static Map<String, Object> buildQuestions() {
        return new Map<String, Object>{
            Q_DAMAGE => TypeSafeQuestions.noul(
                'Does the photo show visible damage to property, equipment or furnishings, such as a crack, tear, dent, stain, leak or broken fixture?',
                'Damage is clearly visible on the item itself.',
                'No damage is visible. Ignore shadows, clutter, reflections, packaging and image quality.'
            ),
            Q_SEVERITY => TypeSafeQuestions.score(
                'How serious is the damage visible in the photo?',
                new List<String>{
                    'None: no damage visible',
                    'Cosmetic: marks or scuffs; everything still works',
                    'Functional: something is broken or cannot be used',
                    'Hazard: unsafe, such as exposed wiring, flooding or broken glass'
                }
            )
        };
    }

    private static TypeSafeConfig openAIConfig() {
        TypeSafeConfig active = TypeSafeConfig.current();
        return active.provider == TypeSafeConfig.ProviderType.OPENAI
            ? active
            : TypeSafeConfig.forProfile(TypeSafeConfig.PROFILE_OPENAI);
    }

    private static Set<Id> pickWithinBudget(List<ContentDocumentLink> links) {
        Set<Id> versionIds = new Set<Id>();
        Integer totalBytes = 0;
        for (ContentDocumentLink link : links) {
            Integer size = link.ContentDocument.ContentSize;
            if (size <= MAX_IMAGE_BYTES && totalBytes + size <= MAX_TOTAL_BYTES) {
                versionIds.add(link.ContentDocument.LatestPublishedVersionId);
                totalBytes += size;
            }
        }
        return versionIds;
    }

    private static void persist(List<Request> requests, List<Response> responses) {
        List<TypeSafe_Log__c> logs = new List<TypeSafe_Log__c>();
        List<Case> caseUpdates = new List<Case>();
        List<Response> caseOwners = new List<Response>();
        Set<Id> queuedCaseIds = new Set<Id>();
        for (Integer i = 0; i < responses.size(); i++) {
            Response response = responses[i];
            if (response.pendingLog != null) {
                logs.add(response.pendingLog);
            }
            // A case asked twice in one call is written once (duplicate Ids fail the whole update).
            if (response.isSuccess && queuedCaseIds.add(requests[i].caseId)) {
                caseUpdates.add(
                    new Case(
                        Id = requests[i].caseId,
                        TS_Visible_Damage__c = response.visibleDamage,
                        TS_Damage_Severity__c = response.damageSeverity
                    )
                );
                caseOwners.add(response);
            }
        }
        TypeSafeLogger.save(logs);
        List<Database.SaveResult> results = Database.update(caseUpdates, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            caseOwners[i].caseUpdated = results[i].isSuccess();
            if (!results[i].isSuccess()) {
                caseOwners[i].errorMessage = 'Case not updated: ' + results[i].getErrors()[0].getMessage();
                caseOwners[i].errorType = String.valueOf(results[i].getErrors()[0].getStatusCode());
            }
        }
        for (Response response : responses) {
            response.logId = response.pendingLog?.Id;
        }
    }

    private static Response fail(Response response, String message, String errorType) {
        response.isSuccess = false;
        response.needsReview = true;
        response.errorMessage = message;
        response.errorType = errorType;
        return response;
    }

    /**
     * Holds what every request in one invocation shares, so checkOne stays small.
     */
    private class Checker {
        private final IDecisionProvider client;
        private final TypeSafeConfig config;
        private final Map<Id, ContentDocumentLink> imageByCaseId;
        private final Map<Id, ContentVersion> versionsById;
        private final Map<String, Object> questions = buildQuestions();

        Checker(
            IDecisionProvider client,
            TypeSafeConfig config,
            Map<Id, ContentDocumentLink> imageByCaseId,
            Map<Id, ContentVersion> versionsById
        ) {
            this.client = client;
            this.config = config;
            this.imageByCaseId = imageByCaseId;
            this.versionsById = versionsById;
        }

        Response checkOne(Request request) {
            Response response = new Response();
            if (request?.caseId == null) {
                return fail(response, 'Case Id is required.', 'VALIDATION');
            }
            ContentDocumentLink link = imageByCaseId.get(request.caseId);
            if (link == null) {
                return fail(response, 'No image file (PNG, JPG, GIF, WEBP) is attached to this case.', 'NO_IMAGE');
            }
            response.contentVersionId = link.ContentDocument.LatestPublishedVersionId;
            response.fileName = link.ContentDocument.Title;
            ContentVersion version = versionsById.get(response.contentVersionId);
            if (version == null) {
                return link.ContentDocument.ContentSize > MAX_IMAGE_BYTES
                    ? fail(response, 'Image is larger than ' + MAX_IMAGE_BYTES + ' bytes.', 'IMAGE_TOO_LARGE')
                    : fail(response, 'Image budget for this transaction used up; run the check again.', 'IMAGE_BUDGET');
            }
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                return fail(response, 'Callout limit reached in this transaction.', 'LIMIT');
            }
            String dataUrl = OpenAIDecisionsClient.toDataUrl(MIME_BY_FILE_TYPE.get(version.FileType), version.VersionData);
            TypeSafeResult result = client.ask(
                new OpenAIDecisionsClient.ImageInput(PROMPT_TEXT, new List<String>{ dataUrl }),
                questions,
                CONTEXT,
                request.caseId
            );
            response.pendingLog = result.log;
            response.model = result.model;
            response.latencyMs = result.latencyMs;
            if (!result.isSuccess) {
                fail(response, result.errorMessage, 'OPENAI_ERROR');
            } else {
                readAnswers(response, result);
            }
            result.log.Outcome__c = response.outcome(config.noulActionThreshold);
            return response;
        }

        private void readAnswers(Response response, TypeSafeResult result) {
            try {
                TypeSafeAnswer severity = result.getAnswer(Q_SEVERITY);
                response.visibleDamage = result.getAnswer(Q_DAMAGE).noul;
                response.damageSeverity = severity.score;
                response.damageSeverityConfidence = severity.confidence;
                Decimal damage = response.visibleDamage ?? 0;
                response.needsReview =
                    (damage >= config.noulReviewThreshold && damage < config.noulActionThreshold) ||
                    (severity.confidence ?? 0) < config.confidenceMin;
                response.isSuccess = true;
            } catch (TypeSafeException e) {
                fail(response, e.getMessage(), e.getTypeName());
            }
        }
    }

    /**
     * Input from Flow or Agentforce.
     */
    public class Request {
        @InvocableVariable(label='Case Id' description='Case whose newest attached image is checked.' required=true)
        public Id caseId;
    }

    /**
     * Output to Flow or Agentforce.
     */
    public class Response {
        @InvocableVariable(label='Visible Damage' description='Probability (0-1) that the photo shows visible damage.')
        public Decimal visibleDamage;

        @InvocableVariable(label='Damage Severity' description='0 None, 1 Cosmetic, 2 Functional, 3 Hazard; probability-weighted.')
        public Decimal damageSeverity;

        @InvocableVariable(label='Severity Confidence' description='Confidence (0-1) in the severity score.')
        public Decimal damageSeverityConfidence;

        @InvocableVariable(label='Needs Review' description='True when the damage answer is in the review band, confidence is low, or the check failed.')
        public Boolean needsReview = false;

        @InvocableVariable(label='Case Updated' description='True when the damage fields were written to the case.')
        public Boolean caseUpdated = false;

        @InvocableVariable(label='Content Version Id' description='The image that was checked.')
        public Id contentVersionId;

        @InvocableVariable(label='File Name' description='Title of the image that was checked.')
        public String fileName;

        @InvocableVariable(label='Model' description='Model that answered.')
        public String model;

        @InvocableVariable(label='Latency (ms)' description='Callout time in milliseconds.')
        public Long latencyMs;

        @InvocableVariable(label='Log Id' description='TypeSafe_Log__c audit record.')
        public Id logId;

        @InvocableVariable(label='Success' description='False when the check could not run.')
        public Boolean isSuccess = false;

        @InvocableVariable(label='Error Message' description='Error details when the check could not run.')
        public String errorMessage;

        @InvocableVariable(label='Error Type' description='Error category when the check could not run.')
        public String errorType;

        // Not exposed to Flow: the unsaved audit record, saved after all callouts.
        public TypeSafe_Log__c pendingLog;

        /**
         * @param actionThreshold Probability at or above which damage counts as present.
         * @return Short outcome for the audit log.
         */
        public String outcome(Decimal actionThreshold) {
            if (!isSuccess) {
                return 'error';
            }
            if (needsReview) {
                return 'needs_review';
            }
            return (visibleDamage ?? 0) >= actionThreshold ? 'damage' : 'no_damage';
        }
    }
}
