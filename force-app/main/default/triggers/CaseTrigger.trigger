/**
 * Case trigger: event routing only. Logic lives in CaseTriggerHandler.
 */
trigger CaseTrigger on Case(before insert, after insert, after update) {
    switch on Trigger.operationType {
        when BEFORE_INSERT {
            CaseTriggerHandler.beforeInsert(Trigger.new);
        }
        when AFTER_INSERT {
            CaseTriggerHandler.afterInsert(Trigger.new);
        }
        when AFTER_UPDATE {
            CaseTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
