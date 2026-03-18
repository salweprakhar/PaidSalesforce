/**
 * @description Handler class for BlockPrice trigger - manages PAID integration logic
 * Detects changes to block pricing and triggers Product updates in PAID
 * Only processes products that use Block pricing method and already have PAID External ID
 * @author m
 * @date 2025
 */
public class BlockPriceTriggerHandler {
    
    private static final String BLOCK_PRICING_METHOD = 'Block';
    
    /**
     * @description Handles after insert events for BlockPrice creation
     * Only triggers update if product already exists in PAID
     * @param newBlockPrices List of newly inserted block prices
     */
    public void handleAfterInsert(List<SBQQ__BlockPrice__c> newBlockPrices) {
        Set<Id> productIds = extractProductIds(newBlockPrices);
        queueProductUpdates(productIds, 'Insert');
    }
    
    /**
     * @description Handles after update events for BlockPrice modifications
     * @param newBlockPrices List of updated block prices
     * @param oldBlockPriceMap Map of old block price versions
     */
    public void handleAfterUpdate(List<SBQQ__BlockPrice__c> newBlockPrices, 
                                  Map<Id, SBQQ__BlockPrice__c> oldBlockPriceMap) {
        Set<Id> productIds = new Set<Id>();
        
        for (SBQQ__BlockPrice__c newBP : newBlockPrices) {
            SBQQ__BlockPrice__c oldBP = oldBlockPriceMap.get(newBP.Id);
            
            // Check if any pricing-related fields changed
            if (hasPricingChanged(newBP, oldBP)) {
                if (newBP.SBQQ__Product__c != null) {
                    productIds.add(newBP.SBQQ__Product__c);
                }
            }
        }
        
        queueProductUpdates(productIds, 'Update');
    }
    
    /**
     * @description Handles after delete events for BlockPrice deletion
     * @param oldBlockPrices List of deleted block prices
     */
    public void handleAfterDelete(List<SBQQ__BlockPrice__c> oldBlockPrices) {
        Set<Id> productIds = extractProductIds(oldBlockPrices);
        queueProductUpdates(productIds, 'Delete');
    }
    
    /**
     * @description Handles after undelete events for BlockPrice restoration
     * @param newBlockPrices List of undeleted block prices
     */
    public void handleAfterUndelete(List<SBQQ__BlockPrice__c> newBlockPrices) {
        Set<Id> productIds = extractProductIds(newBlockPrices);
        queueProductUpdates(productIds, 'Undelete');
    }
    
    /**
     * @description Extracts unique Product IDs from BlockPrice records
     * @param blockPrices List of block price records
     * @return Set of Product2 IDs
     */
    private Set<Id> extractProductIds(List<SBQQ__BlockPrice__c> blockPrices) {
        Set<Id> productIds = new Set<Id>();
        
        for (SBQQ__BlockPrice__c bp : blockPrices) {
            if (bp.SBQQ__Product__c != null) {
                productIds.add(bp.SBQQ__Product__c);
            }
        }
        
        return productIds;
    }
    
    /**
     * @description Checks if pricing-related fields have changed
     * @param newBP Updated block price record
     * @param oldBP Previous version of block price
     * @return true if any pricing field changed
     */
    private Boolean hasPricingChanged(SBQQ__BlockPrice__c newBP, SBQQ__BlockPrice__c oldBP) {
        // Check critical pricing fields
        return newBP.SBQQ__Price__c != oldBP.SBQQ__Price__c ||
               newBP.SBQQ__LowerBound__c != oldBP.SBQQ__LowerBound__c ||
               newBP.SBQQ__UpperBound__c != oldBP.SBQQ__UpperBound__c ||
               newBP.SBQQ__Product__c != oldBP.SBQQ__Product__c;
    }
    
    /**
     * @description Filters products and queues updates to PAID
     * Only processes products that:
     * 1. Use Block pricing method
     * 2. Have PAID External ID (already synced to PAID) - REQUIRED FOR ALL OPERATIONS
     * 3. Are active
     * @param productIds Set of Product IDs to potentially update
     * @param operation Type of operation (Insert, Update, Delete, Undelete)
     */
    private void queueProductUpdates(Set<Id> productIds, String operation) {
        if (productIds.isEmpty()) {
            return;
        }
        
        // Don't process in batch or future context to avoid governor limits
        if (System.isBatch() || System.isFuture()) {
            System.debug('BlockPrice trigger skipped - running in batch/future context');
            return;
        }
        
        // Query products to filter which ones should be updated
        List<Product2> products = [
            SELECT Id, Name, SBQQ__PricingMethod__c, PAID_ProductExternalID__c, 
                   IsActive, Sent_UpdateProduct_to_PAID__c
            FROM Product2
            WHERE Id IN :productIds
        ];
        
        List<Id> productsToUpdate = new List<Id>();
        
        for (Product2 product : products) {
            // CRITICAL: Only process if product has PAID External ID (exists in PAID)
            // This applies to ALL operations including Insert
            if (String.isBlank(product.PAID_ProductExternalID__c)) {
                System.debug('Skipping product ' + product.Name + 
                           ' (' + operation + ') - Not yet synced to PAID (no External ID)');
                continue;
            }
            
            // Only process if:
            // 1. Product is active
            // 2. Product uses Block pricing
            // 3. Not currently being processed
            if (product.IsActive &&
                product.SBQQ__PricingMethod__c == BLOCK_PRICING_METHOD &&
                !product.Sent_UpdateProduct_to_PAID__c) {
                
                productsToUpdate.add(product.Id);
            } else {
                System.debug('Skipping product: ' + product.Name + 
                           ' (' + operation + ')' +
                           ' - Active: ' + product.IsActive + 
                           ', Pricing: ' + product.SBQQ__PricingMethod__c + 
                           ', Already Processing: ' + product.Sent_UpdateProduct_to_PAID__c);
            }
        }
        
        // Queue the update job
        if (!productsToUpdate.isEmpty()) {
            System.debug('Queueing PAID update for ' + productsToUpdate.size() + 
                        ' products due to BlockPrice ' + operation);
            System.enqueueJob(new PAIDProductUpdateQueueable(productsToUpdate));
        } else {
            System.debug('No products qualified for PAID update after BlockPrice ' + operation);
        }
    }
}