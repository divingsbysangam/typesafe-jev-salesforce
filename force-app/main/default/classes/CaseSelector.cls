/**
 * Case queries for the TypeSafe triage flow.
 */
public inherited sharing class CaseSelector {
    private CaseSelector() {
    }

    /**
     * System-mode read for the triage job (see CaseTriageService for why).
     * @param caseIds Cases to load.
     * @return Cases with the fields sent to Jev as state.
     */
    public static List<Case> selectForTriage(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new List<Case>();
        }
        return [
            SELECT Id, Subject, Description, Origin
            FROM Case
            WHERE Id IN :caseIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 200
        ];
    }
}
