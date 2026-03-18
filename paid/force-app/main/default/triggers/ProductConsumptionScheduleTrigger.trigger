trigger ProductConsumptionScheduleTrigger
    on ProductConsumptionSchedule (
        after insert, after update, after delete, after undelete
    ) {

    if (Trigger.isAfter) {
        ProductConsumptionScheduleTriggerHandler.handleAfter(
            Trigger.isDelete ? Trigger.old : Trigger.new
        );
    }
}