/**
 * Case trigger logic for Jev triage. New cases with a subject or description are marked
 * Pending and queued. Setting TS Triage Status back to Pending re-runs triage, which is handy
 * for demos and for retrying errors.
 */
public with sharing class CaseTriggerHandler {
    private CaseTriggerHandler() {
    }

    /**
     * @param newCases Trigger.new
     */
    public static void beforeInsert(List<Case> newCases) {
        for (Case record : newCases) {
            if (record.TS_Triage_Status__c == null && hasText(record)) {
                record.TS_Triage_Status__c = CaseTriageService.STATUS_PENDING;
            }
        }
    }

    /**
     * @param newCases Trigger.new
     */
    public static void afterInsert(List<Case> newCases) {
        Set<Id> pendingIds = new Set<Id>();
        for (Case record : newCases) {
            if (record.TS_Triage_Status__c == CaseTriageService.STATUS_PENDING) {
                pendingIds.add(record.Id);
            }
        }
        enqueue(pendingIds);
    }

    /**
     * @param newCases Trigger.new
     * @param oldCasesById Trigger.oldMap
     */
    public static void afterUpdate(List<Case> newCases, Map<Id, Case> oldCasesById) {
        Set<Id> pendingIds = new Set<Id>();
        for (Case record : newCases) {
            Case previous = oldCasesById.get(record.Id);
            if (
                record.TS_Triage_Status__c == CaseTriageService.STATUS_PENDING &&
                previous?.TS_Triage_Status__c != CaseTriageService.STATUS_PENDING
            ) {
                pendingIds.add(record.Id);
            }
        }
        enqueue(pendingIds);
    }

    private static Boolean hasText(Case record) {
        return String.isNotBlank(record.Subject) || String.isNotBlank(record.Description);
    }

    private static void enqueue(Set<Id> caseIds) {
        if (caseIds.isEmpty()) {
            return;
        }
        // Cases stay Pending if the async limit is already used up; set Pending again to retry.
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(new CaseTriageQueueable(new List<Id>(caseIds)));
    }
}
