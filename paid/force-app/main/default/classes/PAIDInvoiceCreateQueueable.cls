/**
* @description Queueable class to create inoicve in PAID via async callouts
* Separates HTTP callouts from DML operations to comply with Salesforce governor limits
* Can be invoked by triggers or batch jobs
* @author Sumanpreet
* @date 2026

public class PAIDInvoiceCreateQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> invoiceIds;
}
    
    /**
    * @description Constructor
    * @param invoiceIds List of Invoice IDs to create in PAID
   
    public PAIDInvoiceCreateQueueable(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }
    
    /**
    * @description Execute method - processes invocie creation
    * Phase 1: Makes all HTTP callouts (no DML)
    * Phase 2: Performs all DML operations (updates and inserts)
    * @param context Queueable context
   
    public void execute(QueueableContext context) {
    
        System.debug('=== PAID Invoice Create Queueable START ===');
        System.debug('Job ID: ' + context.getJobId());
        System.debug('Processing ' + invoiceIds.size() + ' invoice(s)');
        
    
        // ========== PHASE 1: ALL CALLOUTS (NO DML) ==========
        System.debug('--- Phase 1: Making HTTP Callouts ---');
        List<PAIDInvoiceService.CalloutResult> calloutResults = 
            new List<PAIDInvoiceService.CalloutResult>();
        
        for (Id invoiceId : invoiceIds) {
            try {
                System.debug('Calling PAID API for Invoice ID: ' + invoiceId);
                PAIDInvoiceService.CalloutResult result = 
                    PAIDInvoiceService.createInvoiceCalloutOnly(invoiceId);
                calloutResults.add(result);
                
                System.debug('Callout completed - Success: ' + result.success + 
                             ' | Status Code: ' + result.statusCode);
            } 
            catch (Exception e) {
                // If createInvoiceCalloutOnly itself throws an exception, 
                // create a failed result
                System.debug('Exception during callout: ' + e.getMessage());
                
                PAIDInvoiceService.CalloutResult errorResult = 
                    new PAIDInvoiceService.CalloutResult();
                errorResult.invoiceId = invoiceId;
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
        
        List<blng__Invoice__c> invoicesToUpdate = new List<blng__Invoice__c>();
        List<Event_Log__c> logsToInsert = new List<Event_Log__c>();
        
        Integer successCount = 0;
        Integer failureCount = 0;
        
        
        for (PAIDInvoiceService.CalloutResult result : calloutResults) {
            
            // Build Invoice update record
            blng__Invoice__c invoiceUpdate = new blng__Invoice__c(Id = result.invoiceId);
            
            if (result.success) {
                invoiceUpdate.PAID_InvoiceExternalID__c = result.paidExternalId;
                invoiceUpdate.PAID_Invoice_Creation_Status__c = 'Success';
                invoiceUpdate.Sent_Invoice_to_PAID__c = true;
                successCount++;
                
                System.debug('Invoice ' + result.invoiceId + ' - SUCCESS - PAID ID: ' + result.paidExternalId);
            } else {
                invoiceUpdate.PAID_Invoice_Creation_Status__c = 'Failure';
                invoiceUpdate.PAID_InvoiceExternalID__c = null;
                invoiceUpdate.Sent_Invoice_to_PAID__c = false;
                failureCount++;
                
                System.debug('Invoice ' + result.invoiceId + ' - FAILURE: ' + result.errorMessage);
            }
            
            invoicesToUpdate.add(invoiceUpdate);
            
            Event_Log__c log = PAIDHelper.createEventLog(
                'Create Invoice',                           // operationKey
                result.requestBody,                         // request
                result.responseBody,                        // response
                result.success,                             // success (Boolean)
                truncateErrorMessage(result.errorMessage),  // errorMessage
                null,                                       // accountId
                null,                                       // contactId
                null,                                       // orderId
                result.invoiceId,                           // invoiceId
                null                                        // orderNumber
            );
            
            logsToInsert.add(log);
        }
        
        // Perform Product2 updates
        if (!invoicesToUpdate.isEmpty()) {
            try {
                update invoicesToUpdate;
                System.debug('Successfully updated ' + invoicesToUpdate.size() + 
                             ' Invoice record(s)');
            } catch (DmlException dmlEx) {
                System.debug('ERROR updating Invoice records: ' + dmlEx.getMessage());
                
                // Log individual failures
                for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
                    System.debug('Failed Invoice Index: ' + dmlEx.getDmlIndex(i) + 
                                 ' | Error: ' + dmlEx.getDmlMessage(i));
                }
            } catch (Exception e) {
                System.debug('EXCEPTION updating Invoice records: ' + e.getMessage());
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
*/
public class PAIDInvoiceCreateQueueable{
    
}