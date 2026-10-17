/**
 * Queries for image files attached to cases (Salesforce Files). Runs in user mode: the caller
 * only gets images they are allowed to see.
 */
public inherited sharing class CaseImageSelector {
    private static final Integer MAX_LINKS = 1000;

    private CaseImageSelector() {
    }

    /**
     * Metadata only (no file bytes), newest image first per case.
     * @param caseIds Cases to look at.
     * @param fileTypes ContentDocument.FileType values to accept (e.g. PNG, JPG).
     * @return Newest matching file link by case Id; cases without an image are absent.
     */
    public static Map<Id, ContentDocumentLink> selectLatestImageByCaseId(Set<Id> caseIds, Set<String> fileTypes) {
        Map<Id, ContentDocumentLink> linkByCaseId = new Map<Id, ContentDocumentLink>();
        if (caseIds == null || caseIds.isEmpty() || fileTypes == null || fileTypes.isEmpty()) {
            return linkByCaseId;
        }
        for (ContentDocumentLink link : [
            SELECT
                LinkedEntityId,
                ContentDocumentId,
                ContentDocument.LatestPublishedVersionId,
                ContentDocument.Title,
                ContentDocument.FileType,
                ContentDocument.ContentSize
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :caseIds AND ContentDocument.FileType IN :fileTypes
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT :MAX_LINKS
        ]) {
            if (!linkByCaseId.containsKey(link.LinkedEntityId)) {
                linkByCaseId.put(link.LinkedEntityId, link);
            }
        }
        return linkByCaseId;
    }

    /**
     * Loads file bytes. Keep the Id set small: VersionData counts against the heap limit.
     * @param versionIds ContentVersion Ids.
     * @return Versions with VersionData by Id.
     */
    public static Map<Id, ContentVersion> selectVersionData(Set<Id> versionIds) {
        if (versionIds == null || versionIds.isEmpty()) {
            return new Map<Id, ContentVersion>();
        }
        return new Map<Id, ContentVersion>(
            [SELECT Id, FileType, VersionData FROM ContentVersion WHERE Id IN :versionIds WITH USER_MODE]
        );
    }
}
