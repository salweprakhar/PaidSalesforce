trigger OrderTrigger on Order (before insert, before update, after update) {
     if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            // Populate External IDs from Account and Contact
            OrderTriggerHandler.populateExternalIds(Trigger.new);
        }
    }
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        OrderTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}