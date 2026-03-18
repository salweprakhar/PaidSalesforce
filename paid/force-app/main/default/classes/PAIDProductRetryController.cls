public with sharing class PAIDProductRetryController {
    
    @AuraEnabled
    public static String retryProductSync(Id productId) {
        Event_Log__c log;
        
        try {
            // Query the Product2 with External ID and status
            Product2 product = [
                SELECT Id, Name, ProductCode, PAID_ProductExternalID__c,
                       PAID_Product_Creation_Status__c,
                       PAID_Product_Update_Status__c
                FROM Product2 
                WHERE Id = :productId 
                LIMIT 1
            ];
            
            // Determine if this is a CREATE or UPDATE retry
            Boolean isCreateRetry = String.isBlank(product.PAID_ProductExternalID__c);
            Boolean isUpdateRetry = String.isNotBlank(product.PAID_ProductExternalID__c);
            
            if (isCreateRetry) {
                // Retry CREATE operation (POST)
                System.debug('Retrying product creation for Product2 Id: ' + productId);
                PAIDProductSyncService.createProduct(product.Id);
             } else if (isUpdateRetry) {
                // Retry UPDATE operation (PUT)
                System.debug('Retrying product update for Product2 Id: ' + productId + ', External ID: ' + product.PAID_ProductExternalID__c);
                
                PAIDProductSyncService.updateProduct(product.Id);
             } 

            return 'Product synced successfully in PAID.';
        } catch (Exception e) {
            // Log unexpected exceptions
            log = PAIDHelper.createEventLog(
                'PAID Product Retry Sync',
                'Product2 Id: ' + productId,
                null,
                false,
                'Exception: ' + e.getMessage() + ' | Type: ' + e.getTypeName() + ' | Stack Trace: ' + e.getStackTraceString(),
                null,           // accountId
                null,           // contactId
                null,           // orderId
                productId,      // ProductId
                null            // orderNumber
            );
            insert log;
            
            throw new AuraHandledException('Error syncing product: ' + e.getMessage());
        }
    }
}