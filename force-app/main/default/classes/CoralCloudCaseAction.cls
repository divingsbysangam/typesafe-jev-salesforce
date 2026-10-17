/**
 * Agentforce action for the Coral Cloud Guarded Concierge: files a guest's issue as a Case.
 * The Case trigger then queues Jev triage, so the case arrives typed, prioritised and routed.
 *
 * The agent only sees this action after the TypeSafe guardrail returned "pass" for the turn
 * (`available when` in the agent script), so nothing is filed for a blocked message.
 */
public with sharing class CoralCloudCaseAction {
    public static final String ORIGIN = 'Agentforce';
    private static final Integer MAX_SUBJECT = 255;
    private static final Integer MAX_DESCRIPTION = 32000;

    /**
     * Creates one Case per request and returns its number.
     * @param requests Guest issues captured by the agent.
     * @return One response per request, in order.
     */
    @InvocableMethod(
        label='Coral Cloud: Create Support Case'
        description='Files the guest\'s issue as a support case and returns the case number to share with the guest.'
        category='TypeSafe'
    )
    public static List<Response> createCases(List<Request> requests) {
        List<Response> responses = new List<Response>();
        List<Case> toInsert = new List<Case>();
        List<Response> pending = new List<Response>();

        for (Request request : requests ?? new List<Request>()) {
            Response response = new Response();
            responses.add(response);
            if (request == null || String.isBlank(request.subject) || String.isBlank(request.description)) {
                response.errorMessage = 'Subject and description are required.';
                response.errorType = 'VALIDATION';
                continue;
            }
            toInsert.add(
                new Case(
                    Subject = request.subject.abbreviate(MAX_SUBJECT),
                    Description = request.description.abbreviate(MAX_DESCRIPTION),
                    SuppliedEmail = String.isBlank(request.guestEmail) ? null : request.guestEmail.trim(),
                    Origin = ORIGIN
                )
            );
            pending.add(response);
        }
        if (toInsert.isEmpty()) {
            return responses;
        }

        // System mode: the agent user files cases but should not need broad Case CRUD/FLS.
        List<Database.SaveResult> results = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        Set<Id> insertedIds = new Set<Id>();
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                insertedIds.add(result.getId());
            }
        }
        Map<Id, String> caseNumbersById = insertedIds.isEmpty()
            ? new Map<Id, String>()
            : new CaseNumberReader().readNumbers(insertedIds);

        for (Integer i = 0; i < results.size(); i++) {
            Response response = pending[i];
            Database.SaveResult result = results[i];
            if (result.isSuccess()) {
                response.caseId = result.getId();
                response.caseNumber = caseNumbersById.get(result.getId());
                response.isSuccess = true;
            } else {
                response.errorMessage = result.getErrors()[0].getMessage();
                response.errorType = String.valueOf(result.getErrors()[0].getStatusCode());
            }
        }
        return responses;
    }

    /**
     * Reads back case numbers for cases this action just created. Without sharing because demo-org
     * and assignment-rule automation can move a new case to a queue the agent user can't see.
     * It only reads CaseNumber for the Ids inserted in this same call.
     */
    private without sharing class CaseNumberReader {
        /**
         * @param caseIds Cases created in this call.
         * @return CaseNumber by Id.
         */
        public Map<Id, String> readNumbers(Set<Id> caseIds) {
            Map<Id, String> caseNumbersById = new Map<Id, String>();
            for (Case record : [SELECT Id, CaseNumber FROM Case WHERE Id IN :caseIds WITH SYSTEM_MODE]) {
                caseNumbersById.put(record.Id, record.CaseNumber);
            }
            return caseNumbersById;
        }
    }

    /**
     * Input from the agent.
     */
    public class Request {
        @InvocableVariable(label='Subject' description='Short summary of the guest\'s issue.' required=true)
        public String subject;

        @InvocableVariable(label='Description' description='The guest\'s issue in their own words.' required=true)
        public String description;

        @InvocableVariable(label='Guest Email' description='Guest email address, if they gave one.')
        public String guestEmail;
    }

    /**
     * Output to the agent.
     */
    public class Response {
        @InvocableVariable(label='Case Number' description='Case number to share with the guest.')
        public String caseNumber;

        @InvocableVariable(label='Case Id' description='Salesforce Id of the new case.')
        public String caseId;

        @InvocableVariable(label='Success' description='True when the case was created.')
        public Boolean isSuccess = false;

        @InvocableVariable(label='Error Message' description='Why the case could not be created.')
        public String errorMessage;

        @InvocableVariable(label='Error Type' description='Error category.')
        public String errorType;
    }
}
