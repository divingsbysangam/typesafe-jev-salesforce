/**
 * Runs Jev case triage off the trigger transaction (triggers cannot make callouts). It handles
 * BATCH_SIZE cases per run and chains for the rest. Cases that hit a 429/529 are retried in a
 * later run with a one-minute delay, up to MAX_ATTEMPTS.
 *
 * @example
 * System.enqueueJob(new CaseTriageQueueable(new List<Id>{ caseId }));
 */
public with sharing class CaseTriageQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer BATCH_SIZE = 50;
    @TestVisible
    private static final Integer MAX_ATTEMPTS = 3;
    private static final Integer MAX_CHAIN_DEPTH = 20;
    private static final Integer RETRY_DELAY_MINUTES = 1;

    private final List<Id> caseIds;
    private final Integer attempt;
    private final Integer chainDepth;

    /**
     * @param caseIds Cases to triage.
     */
    public CaseTriageQueueable(List<Id> caseIds) {
        this(caseIds, 1, 0);
    }

    @TestVisible
    private CaseTriageQueueable(List<Id> caseIds, Integer attempt, Integer chainDepth) {
        this.caseIds = caseIds ?? new List<Id>();
        this.attempt = attempt;
        this.chainDepth = chainDepth;
    }

    /**
     * @param context Queueable context.
     */
    public void execute(QueueableContext context) {
        if (caseIds.isEmpty()) {
            return;
        }
        Set<Id> batchIds = new Set<Id>();
        List<Id> remainingIds = new List<Id>();
        for (Id caseId : caseIds) {
            if (batchIds.size() < BATCH_SIZE) {
                batchIds.add(caseId);
            } else {
                remainingIds.add(caseId);
            }
        }

        Set<Id> retryIds = new Set<Id>();
        try {
            retryIds = CaseTriageService.triage(batchIds, attempt < MAX_ATTEMPTS);
        } catch (Exception e) {
            CaseTriageService.markError(batchIds, 'Triage job failed: ' + e.getTypeName() + ': ' + e.getMessage());
        }
        chainNext(remainingIds, retryIds);
    }

    private void chainNext(List<Id> remainingIds, Set<Id> retryIds) {
        if (remainingIds.isEmpty() && retryIds.isEmpty()) {
            return;
        }
        List<Id> nextIds = new List<Id>(remainingIds);
        nextIds.addAll(retryIds);
        if (chainDepth >= MAX_CHAIN_DEPTH) {
            CaseTriageService.markError(new Set<Id>(nextIds), 'Triage chain depth limit reached; set status to Pending to retry.');
            return;
        }
        if (Test.isRunningTest()) {
            return;
        }
        // Retries back off; a job only carries the retry counter forward when it contains retries.
        Boolean hasRetries = !retryIds.isEmpty();
        CaseTriageQueueable next = new CaseTriageQueueable(nextIds, hasRetries ? attempt + 1 : attempt, chainDepth + 1);
        System.enqueueJob(next, hasRetries ? RETRY_DELAY_MINUTES : 0);
    }
}
