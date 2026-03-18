/**
 * @description Handler class for PricebookEntryChangeEvent trigger
 * Processes CDC events and syncs products to PAID in real-time
 * 
 * @author Your Name
 * @date 2025-12-19
 */
public class PricebookEntryChangeHandler {
    
    // Fields to monitor for changes
    private static final Set<String> MONITORED_FIELDS = new Set<String>{
        'UnitPrice',
        'IsActive'
    };
    
    /**
     * @description Handles after insert of PricebookEntryChangeEvent
     * Identifies products that need to be synced to PAID
     * 
     * @param changeEvents List of PricebookEntryChangeEvent records
     */
    public static void handleAfterInsert(List<PricebookEntryChangeEvent> changeEvents) {
        
        // Collect Product IDs that need to be synced
        Set<Id> productIdsToSync = new Set<Id>();
        
        for (PricebookEntryChangeEvent event : changeEvents) {
            
            // Get the change event header
            EventBus.ChangeEventHeader header = event.ChangeEventHeader;
            
            // Process CREATE and UPDATE events only
            if (header.changeType == 'CREATE' || header.changeType == 'UPDATE') {
                
                if (shouldSyncProduct(event, header)) {
                    productIdsToSync.add(event.Product2Id);
                }
            }
        }
        
        // If we have products to sync, enqueue them
        if (!productIdsToSync.isEmpty()) {
            enqueuePAIDSync(productIdsToSync);
        }
    }
    
    /**
     * @description Determines if a product should be synced to PAID
     * 
     * @param event The PricebookEntryChangeEvent
     * @param header The EventBus.ChangeEventHeader
     * @return Boolean true if product should be synced
     */
    private static Boolean shouldSyncProduct(
        PricebookEntryChangeEvent event, 
        EventBus.ChangeEventHeader header
    ) {
        
        // Product2Id must exist
        if (event.Product2Id == null) {
            System.debug('CDC Event skipped: No Product2Id');
            return false;
        }
        
        // PricebookEntry must be active
        if (event.IsActive != true) {
            System.debug('CDC Event skipped: PricebookEntry is not active');
            return false;
        }
        
        // For CREATE events - always sync
        if (header.changeType == 'CREATE') {
            System.debug('CDC CREATE detected for Product: ' + event.Product2Id);
            return true;
        }
        
        // For UPDATE events - check if monitored fields changed
        if (header.changeType == 'UPDATE') {
            List<String> changedFields = header.changedFields;
            
            if (changedFields != null && !changedFields.isEmpty()) {
                for (String field : changedFields) {
                    if (MONITORED_FIELDS.contains(field)) {
                        System.debug('CDC UPDATE detected - Field changed: ' + field + 
                                   ' for Product: ' + event.Product2Id);
                        return true;
                    }
                }
            }
            
            System.debug('CDC UPDATE skipped: No monitored fields changed for Product: ' + 
                        event.Product2Id);
        }
        
        return false;
    }
    
     /**
     * @description Enqueues products for PAID sync directly via queueable
     * Validates products meet sync criteria before enqueueing
     * 
     * @param productIds Set of Product2 IDs to sync
     */
    private static void enqueuePAIDSync(Set<Id> productIds) {
        
        if (productIds.isEmpty()) {
            return;
        }
        
        // Query products to validate they're ready for sync
        Map<Id, Product2> productsToUpdate = new Map<Id, Product2>([
            SELECT Id, Sent_Product_to_PAID__c, Sent_UpdateProduct_to_PAID__c, 
                   IsActive, PAID_ProductExternalID__c
            FROM Product2
            WHERE Id IN :productIds
            AND Sent_Product_to_PAID__c = true
            AND Sent_UpdateProduct_to_PAID__c = false
            AND IsActive = true
            AND PAID_ProductExternalID__c != null  // ✅ MUST have External ID
        ]);
        
        if (!productsToUpdate.isEmpty()) {
            System.debug('Enqueuing ' + productsToUpdate.size() + ' product(s) for PAID sync via CDC');
            
            // Directly enqueue the queueable
            List<Id> productIdList = new List<Id>(productsToUpdate.keySet());
        System.enqueueJob(new PAIDProductUpdateQueueable(productIdList));
        } else {
            System.debug('No products qualified for PAID sync - validation criteria not met');
        }
    }
}