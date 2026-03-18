/**
* @description Queueable class to create products in PAID via async callouts
* Separates HTTP callouts from DML operations to comply with Salesforce governor limits
* Can be invoked by triggers or batch jobs
* @author Manusha T
* @date 2025
*/
public class PAIDProductCreateQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> productIds;
    
    /**
* @description Constructor
* @param productIds List of Product2 IDs to create in PAID
*/
    public PAIDProductCreateQueueable(List<Id> productIds) {
        this.productIds = productIds;
    }
    
    /**
* @description Execute method - processes product creation
* Phase 1: Makes all HTTP callouts (no DML)
* Phase 2: Performs all DML operations (updates and inserts)
* @param context Queueable context
*/
    public void execute(QueueableContext context) {
        System.debug('=== PAID Product Create Queueable START ===');
        System.debug('Job ID: ' + context.getJobId());
        System.debug('Processing ' + productIds.size() + ' product(s)');
        
        // ========== PHASE 1: ALL CALLOUTS (NO DML) ==========
        System.debug('--- Phase 1: Making HTTP Callouts ---');
        List<PAIDProductService.CalloutResult> calloutResults = 
            new List<PAIDProductService.CalloutResult>();
        
        for (Id productId : productIds) {
            try {
                System.debug('Calling PAID API for Product ID: ' + productId);
                PAIDProductService.CalloutResult result = 
                    PAIDProductService.createProductCalloutOnly(productId);
                calloutResults.add(result);
                
                System.debug('Callout completed - Success: ' + result.success + 
                             ' | Status Code: ' + result.statusCode);
                
            } catch (Exception e) {
                // If createProductCalloutOnly itself throws an exception, 
                // create a failed result
                System.debug('Exception during callout: ' + e.getMessage());
                
                PAIDProductService.CalloutResult errorResult = 
                    new PAIDProductService.CalloutResult();
                errorResult.productId = productId;
                errorResult.success = false;
                errorResult.errorMessage = 'Exception during callout: ' + 
                    e.getMessage() + ' | Stack: ' + e.getStackTraceString();
                errorResult.requestBody = 'Failed to generate request';
                
                calloutResults.add(errorResult);
            }
        }
        
        System.debug('Completed ' + calloutResults.size() + ' callout(s)');
        
        // ========== PHASE 2: ALL DML AFTER CALLOUTS ==========
        System.debug('--- Phase 2: Performing DML Operations ---');
        
        List<Product2> productsToUpdate = new List<Product2>();
        List<Event_Log__c> logsToInsert = new List<Event_Log__c>();
        
        Integer successCount = 0;
        Integer failureCount = 0;
        
        for (PAIDProductService.CalloutResult result : calloutResults) {
            
            // Build Product2 update record
            Product2 productUpdate = new Product2(Id = result.productId);
            
            if (result.success) {
                productUpdate.PAID_ProductExternalID__c = result.paidExternalId;
                productUpdate.PAID_Product_Creation_Status__c = 'Success';
                productUpdate.Sent_Product_to_PAID__c = true;
                successCount++;
                
                System.debug('Product ' + result.productId + ' - SUCCESS - PAID ID: ' + result.paidExternalId);
            } else {
                productUpdate.PAID_Product_Creation_Status__c = 'Failure';
                productUpdate.PAID_ProductExternalID__c = null;
                productUpdate.Sent_Product_to_PAID__c = false;
                failureCount++;
                
                System.debug('Product ' + result.productId + ' - FAILURE: ' + result.errorMessage);
            }
            
            productsToUpdate.add(productUpdate);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                'Create Product',                           // operationKey
                result.requestBody,                         // request
                result.responseBody,                        // response
                result.success,                             // success (Boolean)
                truncateErrorMessage(result.errorMessage),  // errorMessage
                null,                                       // accountId
                null,                                       // contactId
                null,                                       // orderId
                result.productId,                           // productId
                null                                        // orderNumber
            );
            
            logsToInsert.add(log);
        }
        
        // Perform Product2 updates
        if (!productsToUpdate.isEmpty()) {
            try {
                update productsToUpdate;
                System.debug('Successfully updated ' + productsToUpdate.size() + 
                             ' Product2 record(s)');
            } catch (DmlException dmlEx) {
                System.debug('ERROR updating Product2 records: ' + dmlEx.getMessage());
                
                // Log individual failures
                for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
                    System.debug('Failed Product Index: ' + dmlEx.getDmlIndex(i) + 
                                 ' | Error: ' + dmlEx.getDmlMessage(i));
                }
            } catch (Exception e) {
                System.debug('EXCEPTION updating Product2 records: ' + e.getMessage());
            }
        }
        
        // Perform Event_Log__c inserts
        if (!logsToInsert.isEmpty()) {
            try {
                insert logsToInsert;
                System.debug('Successfully created ' + logsToInsert.size() + 
                             ' Event_Log__c record(s)');
            } catch (DmlException dmlEx) {
                System.debug('ERROR creating Event_Log__c records: ' + dmlEx.getMessage());
                
                // Log individual failures
                for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
                    System.debug('Failed Log Index: ' + dmlEx.getDmlIndex(i) + 
                                 ' | Error: ' + dmlEx.getDmlMessage(i));
                }
            } catch (Exception e) {
                System.debug('EXCEPTION creating Event_Log__c records: ' + e.getMessage());
            }
        }
        
        // Final summary
        System.debug('=== PAID Product Create Queueable COMPLETE ===');
        System.debug('Total Products Processed: ' + calloutResults.size());
        System.debug('Successful Creations: ' + successCount);
        System.debug('Failed Creations: ' + failureCount);
    }
    
    /**
* @description Truncates error message to fit within field limits
* @param errorMessage Error message to truncate
* @return Truncated error message or null if input is null
*/
    private String truncateErrorMessage(String errorMessage) {
        if (errorMessage == null) {
            return null;
        }
        
        Integer maxLength = 32768; // Adjust based on your Error_Message__c field definition
        
        if (errorMessage.length() <= maxLength) {
            return errorMessage;
        }
        
        return errorMessage.substring(0, maxLength - 15) + '...[TRUNCATED]';
    }
}