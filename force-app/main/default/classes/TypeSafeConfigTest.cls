@IsTest
private class TypeSafeConfigTest {
    @IsTest
    static void shouldUseDefaults_WhenSettingMissing() {
        TypeSafeConfig config = TypeSafeConfig.fromSetting(null);

        Assert.areEqual('jev-latest', config.model, 'Default model should be jev-latest');
        Assert.areEqual(10000, config.timeoutMs, 'Default timeout should be 10s');
        Assert.areEqual(0.7, config.confidenceMin, 'Default confidence floor should be 0.7');
        Assert.areEqual(0.35, config.noulReviewThreshold, 'Default review threshold should be 0.35');
        Assert.areEqual(0.7, config.noulActionThreshold, 'Default action threshold should be 0.7');
        Assert.areEqual(2.0, config.severityBlock, 'Default severity block should be 2.0');
    }

    @IsTest
    static void shouldReadValues_WhenSettingPopulated() {
        TypeSafe_Setting__mdt setting = new TypeSafe_Setting__mdt(
            Model__c = 'jev-1.13.0',
            Timeout_Ms__c = 5000,
            Confidence_Min__c = 0.8,
            Noul_Review_Threshold__c = 0.4,
            Noul_Action_Threshold__c = 0.9,
            Severity_Block__c = 2.5
        );

        TypeSafeConfig config = TypeSafeConfig.fromSetting(setting);

        Assert.areEqual('jev-1.13.0', config.model, 'Model should come from the setting');
        Assert.areEqual(5000, config.timeoutMs, 'Timeout should come from the setting');
        Assert.areEqual(0.8, config.confidenceMin, 'Confidence floor should come from the setting');
        Assert.areEqual(0.4, config.noulReviewThreshold, 'Review threshold should come from the setting');
        Assert.areEqual(0.9, config.noulActionThreshold, 'Action threshold should come from the setting');
        Assert.areEqual(2.5, config.severityBlock, 'Severity block should come from the setting');
    }

    @IsTest
    static void shouldClampTimeout_WhenAboveApexMaximum() {
        TypeSafe_Setting__mdt setting = new TypeSafe_Setting__mdt(Timeout_Ms__c = 999999);

        TypeSafeConfig config = TypeSafeConfig.fromSetting(setting);

        Assert.areEqual(120000, config.timeoutMs, 'Timeout should be clamped to the Apex maximum');
    }

    @IsTest
    static void shouldCacheConfig_WhenCurrentCalledTwice() {
        TypeSafeConfig first = TypeSafeConfig.current();

        TypeSafeConfig second = TypeSafeConfig.current();

        Assert.areEqual(first, second, 'current() should return the cached instance');
    }
}
