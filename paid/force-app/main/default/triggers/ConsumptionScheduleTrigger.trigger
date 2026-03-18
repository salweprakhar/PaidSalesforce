trigger ConsumptionScheduleTrigger on ConsumptionSchedule (
    after insert, after update, after delete, after undelete
) {
    ConsumptionScheduleTriggerHandler handler =
        new ConsumptionScheduleTriggerHandler();

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            handler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            handler.handleAfterDelete(Trigger.old);
        }
        if (Trigger.isUndelete) {
            handler.handleAfterUndelete(Trigger.new);
        }
    }
}