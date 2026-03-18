/**
 * @description Trigger for Product2 object to handle PAID integration
 * @author manusha T
 * @date 2025
 */
trigger PAIDProductTrigger on Product2 (after insert, after update) {
    PAIDProductTriggerHandler handler = new PAIDProductTriggerHandler();
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
           handler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
           handler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}