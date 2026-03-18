trigger ConsumptionRateTrigger
    on ConsumptionRate (
        after insert, after update, after delete, after undelete
    ) {

    if (Trigger.isAfter) {
        ConsumptionRateTriggerHandler.handleAfter(
            Trigger.isDelete ? Trigger.old : Trigger.new
        );
    }
}