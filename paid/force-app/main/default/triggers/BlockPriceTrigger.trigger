/**
 * @description Trigger for SBQQ__BlockPrice__c object to handle PAID integration
 * Monitors changes to block pricing and triggers Product updates in PAID
 * @author m
 * @date 2025
 */
trigger BlockPriceTrigger on SBQQ__BlockPrice__c (after insert, after update, after delete, after undelete) {
    BlockPriceTriggerHandler handler = new BlockPriceTriggerHandler();
    
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