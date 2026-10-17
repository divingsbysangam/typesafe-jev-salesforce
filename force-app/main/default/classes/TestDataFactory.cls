/**
 * Test data for the TypeSafe project.
 */
@IsTest
public class TestDataFactory {
    public static final String TYPESAFE_USER_LAST_NAME = 'TypeSafeTestUser';
    private static final String PERMISSION_SET = 'TypeSafe_User';
    private static final String PROFILE = 'Standard User';
    private static final String SDO_CASE_HELPER = 'SDO_Service_Einstein_Agent_Helper__c';

    /**
     * Creates a Standard User with the TypeSafe_User permission set (FLS on the new fields,
     * access to the API key principal).
     * @return The inserted user.
     */
    public static User createTypeSafeUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = :PROFILE LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User testUser = new User(
            LastName = TYPESAFE_USER_LAST_NAME,
            Alias = 'tsuser',
            Email = 'typesafe.test@example.com',
            Username = 'typesafe.test.' + unique + '@example.com',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        PermissionSet typeSafePermissions = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = typeSafePermissions.Id);
        return testUser;
    }

    /**
     * Gives the running user the TypeSafe_User permission set (FLS on the TS_* fields and the log).
     * Runs as that user so the setup-object insert doesn't mix with later record DML.
     */
    public static void grantTypeSafePermissionsToRunningUser() {
        User runningUser = new User(Id = UserInfo.getUserId());
        System.runAs(runningUser) {
            PermissionSet typeSafePermissions = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET LIMIT 1];
            // The org admin may already hold it (real assignments are visible to tests).
            Integer existing = [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :runningUser.Id AND PermissionSetId = :typeSafePermissions.Id
            ];
            if (existing == 0) {
                insert new PermissionSetAssignment(AssigneeId = runningUser.Id, PermissionSetId = typeSafePermissions.Id);
            }
        }
    }

    /**
     * Attaches a file to a case through Salesforce Files.
     * @param caseId Case to attach to.
     * @param fileName File name; its extension sets ContentDocument.FileType (e.g. damage.png -> PNG).
     * @param data File bytes.
     * @return The inserted version.
     */
    public static ContentVersion createCaseFile(Id caseId, String fileName, Blob data) {
        ContentVersion version = new ContentVersion(
            Title = fileName.substringBeforeLast('.'),
            PathOnClient = fileName,
            VersionData = data,
            FirstPublishLocationId = caseId
        );
        insert version;
        return version;
    }

    /**
     * @return The user created by createTypeSafeUser().
     */
    public static User getTypeSafeUser() {
        return [SELECT Id FROM User WHERE LastName = :TYPESAFE_USER_LAST_NAME LIMIT 1];
    }

    /**
     * @param count Number of cases.
     * @param triageStatus Initial TS Triage Status. Use a non-null, non-Pending value (e.g. Error)
     *        to keep the trigger from queueing triage during setup.
     * @param doInsert Insert the records when true.
     * @return The cases.
     */
    public static List<Case> createCases(Integer count, String triageStatus, Boolean doInsert) {
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            cases.add(
                new Case(
                    Subject = 'Payouts failing ' + i,
                    Description = 'Help! My payouts have been failing for 3 days and my customers are angry.',
                    Origin = 'Email',
                    TS_Triage_Status__c = triageStatus
                )
            );
        }
        if (doInsert) {
            prepareDemoOrgCaseAutomation();
            insert cases;
        }
        return cases;
    }

    /**
     * Salesforce demo orgs (SDO) ship a Case-on-create process whose Einstein classification demo
     * flow fails when no active SDO_Service_Einstein_Agent_Helper__c exists, which is always the
     * case in a test. Create one inert helper (it never matches a case) so Case inserts succeed.
     * Does nothing in orgs without the SDO object, so the project stays portable.
     */
    public static void prepareDemoOrgCaseAutomation() {
        Schema.SObjectType helperType = Schema.getGlobalDescribe().get(SDO_CASE_HELPER);
        if (helperType == null) {
            return;
        }
        if (Database.countQuery('SELECT COUNT() FROM ' + SDO_CASE_HELPER + ' WHERE Active__c = true') > 0) {
            return;
        }
        SObject helper = helperType.newSObject();
        helper.put('Active__c', true);
        helper.put('Field__c', 'Subject');
        helper.put('Comparator__c', 'EQ');
        helper.put('Value__c', 'typesafe-test-value-that-never-matches');
        insert helper;
    }
}
