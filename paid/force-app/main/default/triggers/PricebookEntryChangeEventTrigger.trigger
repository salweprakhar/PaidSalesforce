trigger PricebookEntryChangeEventTrigger on PricebookEntryChangeEvent (after insert) {
    
    System.debug('========================================');
    System.debug('🎉 CDC TRIGGER FIRED!!!');
    System.debug('Event Count: ' + Trigger.new.size());
    System.debug('Timestamp: ' + System.now());
    System.debug('========================================');
    
    for (PricebookEntryChangeEvent event : Trigger.new) {
        System.debug('');
        System.debug('--- CDC Event Details ---');
        
        // Get the header
        EventBus.ChangeEventHeader header = event.ChangeEventHeader;
        
        // Log the change type (CREATE, UPDATE, DELETE, etc.)
        System.debug('Change Type: ' + header.changeType);
        
        // Log which records changed
        System.debug('Record IDs: ' + header.recordIds);
        
        // Log which fields changed (for UPDATE events)
        System.debug('Changed Fields: ' + header.changedFields);
        
        // Log entity name
        System.debug('Entity Name: ' + header.entityName);
        
        // Log transaction key
        System.debug('Transaction Key: ' + header.transactionKey);
        
        // Log commit timestamp
        System.debug('Commit Timestamp: ' + header.commitTimestamp);
        
        // Log commit number
        System.debug('Commit Number: ' + header.commitNumber);
        
        // Try to log the actual field values if available
        try {
            System.debug('UnitPrice: ' + event.UnitPrice);
            System.debug('IsActive: ' + event.IsActive);
            System.debug('Product2Id: ' + event.Product2Id);
            System.debug('Pricebook2Id: ' + event.Pricebook2Id);
        } catch (Exception e) {
            System.debug('Could not access field values: ' + e.getMessage());
        }
        
        System.debug('-------------------------');
    }
    
    System.debug('========================================');
    System.debug('✅ CDC Trigger Processing Complete');
    System.debug('========================================');
}