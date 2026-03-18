trigger CostTrigger on SBQQ__Cost__c (after insert, after update, after delete, after undelete) {
 CostTriggerHandler handler = new CostTriggerHandler();
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            handler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            handler.handleAfterDelete(Trigger.old);
        } else if (Trigger.isUndelete) {
            handler.handleAfterUndelete(Trigger.new);
        }
    }
}