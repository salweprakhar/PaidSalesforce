public class CostTriggerHandler {
private static final String COST_PRICING_METHOD = 'Cost';
    public void handleAfterInsert(List<SBQQ__Cost__c> newcost) {
        Set<Id> productIds = extractProductIds(newcost);
        queueProductUpdates(productIds, 'Insert');
    }
    
    public void handleAfterUpdate(List<SBQQ__Cost__c> newcost, 
                                  Map<Id, SBQQ__Cost__c> oldCostMap) {
        Set<Id> productIds = new Set<Id>();
        
        for (SBQQ__Cost__c newCT : newcost) {
            SBQQ__Cost__c oldCT = oldCostMap.get(newCT.Id);
            
            if (hasPricingChanged(newCT, oldCT)) {
                if (newCT.SBQQ__Product__c != null) {
                    productIds.add(newCT.SBQQ__Product__c);
                }
            }
        }
        
        queueProductUpdates(productIds, 'Update');
    }
    
    public void handleAfterDelete(List<SBQQ__Cost__c> oldCost) {
        Set<Id> productIds = extractProductIds(oldCost);
        queueProductUpdates(productIds, 'Delete');
    }
    
    public void handleAfterUndelete(List<SBQQ__Cost__c> newCost) {
        Set<Id> productIds = extractProductIds(newCost);
        queueProductUpdates(productIds, 'Undelete');
    }
    
    private Set<Id> extractProductIds(List<SBQQ__Cost__c> costs) {
        Set<Id> productIds = new Set<Id>();
        
        for (SBQQ__Cost__c ct : costs) {
            if (ct.SBQQ__Product__c != null) {
                productIds.add(ct.SBQQ__Product__c);
            }
        }
        
        return productIds;
    }
    
    private Boolean hasPricingChanged(SBQQ__Cost__c newCT, SBQQ__Cost__c oldCT) {
        return newCT.SBQQ__Product__c != oldCT.SBQQ__Product__c ||
            newCT.SBQQ__Active__c  != oldCT.SBQQ__Active__c ||
               newCT.SBQQ__UnitCost__c != oldCT.SBQQ__UnitCost__c;
    }
    
    private void queueProductUpdates(Set<Id> productIds, String operation) {
        if (productIds.isEmpty()) {
            return;
        }
        
        if (System.isBatch() || System.isFuture()) {
            System.debug('BlockPrice trigger skipped - running in batch/future context');
            return;
        }
        
        List<Product2> products = [
            SELECT Id, Name, SBQQ__PricingMethod__c, PAID_ProductExternalID__c, 
                   IsActive, Sent_UpdateProduct_to_PAID__c
            FROM Product2
            WHERE Id IN :productIds
        ];
        
        List<Id> productsToUpdate = new List<Id>();
        
        for (Product2 product : products) {
            if (String.isBlank(product.PAID_ProductExternalID__c)) {
                System.debug('Skipping product ' + product.Name + 
                           ' (' + operation + ') - Not yet synced to PAID (no External ID)');
                continue;
            }
            
            if (product.IsActive &&
                product.SBQQ__PricingMethod__c == COST_PRICING_METHOD &&
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
            System.debug('productsToUpdate::'+productsToUpdate);
            System.enqueueJob(new PAIDProductUpdateQueueable(productsToUpdate));
        } else {
            System.debug('No products qualified for PAID update after BlockPrice ' + operation);
        }
    }
}