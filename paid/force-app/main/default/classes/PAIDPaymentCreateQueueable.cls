/**
* @description Queueable class to create payment in PAID via async callouts
* @author Him
* @date 2026
*/
public class PAIDPaymentCreateQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> paymentIds;

    /**
    * @description Constructor
    * @param paymentIds List of Payment IDs to create in PAID
    */
    public PAIDPaymentCreateQueueable(List<Id> paymentIds) {
        this.paymentIds = paymentIds;
    }

    /**
    * @description Execute method - processes payment creation
    * Phase 1: Makes all HTTP callouts (no DML)
    * Phase 2: Performs all DML operations (updates and inserts)
    * @param context Queueable context
    */
    public void execute(QueueableContext context) {

        System.debug('=== PAID Payment Create Queueable START ===');
        System.debug('Job ID: ' + context.getJobId());
        System.debug('Processing ' + paymentIds.size() + ' payment(s)');

        // ========== PHASE 1: ALL CALLOUTS (NO DML) ==========
        System.debug('--- Phase 1: Making HTTP Callouts ---');

        List<PAIDPaymentService.CalloutResult> calloutResults =
            new List<PAIDPaymentService.CalloutResult>();

        for (Id paymentId : paymentIds) {
            try {
                System.debug('Calling PAID API for Payment ID: ' + paymentId);

                PAIDPaymentService.CalloutResult result =
                    PAIDPaymentService.createPaymentCalloutOnly(paymentId);

                calloutResults.add(result);

                System.debug('Callout completed - Success: ' + result.success +
                             ' | Status Code: ' + result.statusCode);

            } catch (Exception e) {
                System.debug('Exception during callout: ' + e.getMessage());

                PAIDPaymentService.CalloutResult errorResult =
                    new PAIDPaymentService.CalloutResult();
                errorResult.paymentId = paymentId;
                errorResult.success = false;
                errorResult.errorMessage =
                    'Exception during callout: ' + e.getMessage() +
                    ' | Stack: ' + e.getStackTraceString();
                errorResult.requestBody = 'Failed to generate request';

                calloutResults.add(errorResult);
            }
        }

        System.debug('Completed ' + calloutResults.size() + ' callout(s)');

        // ========== PHASE 2: ALL DML AFTER CALLOUTS ==========
        System.debug('--- Phase 2: Performing DML Operations ---');

        List<Payment> paymentsToUpdate = new List<Payment>(); // change object if needed
        List<Event_Log__c> logsToInsert = new List<Event_Log__c>();

        Integer successCount = 0;
        Integer failureCount = 0;

        for (PAIDPaymentService.CalloutResult result : calloutResults) {

            Payment paymentUpdate = new Payment(Id = result.paymentId);

            if (result.success) {
                // paymentUpdate.PAID_PaymentExternalID__c = result.paidExternalId;
                // paymentUpdate.PAID_Payment_Creation_Status__c = 'Success';
                // paymentUpdate.Sent_Payment_to_PAID__c = true;
                successCount++;

                System.debug('Payment ' + result.paymentId + ' - SUCCESS - PAID ID: ' + result.paidExternalId);
            } else {
                // paymentUpdate.PAID_Payment_Creation_Status__c = 'Failure';
                // paymentUpdate.PAID_PaymentExternalID__c = null;
                // paymentUpdate.Sent_Payment_to_PAID__c = false;
                failureCount++;

                System.debug('Payment ' + result.paymentId + ' - FAILURE: ' + result.errorMessage);
            }

            paymentsToUpdate.add(paymentUpdate);

            Event_Log__c log = PAIDHelper.createEventLog(
                'Create Payment',                          // operationKey
                result.requestBody,                        // request
                result.responseBody,                       // response
                result.success,                            // success
                truncateErrorMessage(result.errorMessage), // errorMessage
                null,                                      // accountId
                null,                                      // contactId
                null,                                      // orderId
                result.paymentId,                          // paymentId
                null                                       // orderNumber
            );

            logsToInsert.add(log);
        }

        if (!paymentsToUpdate.isEmpty()) {
            try {
                update paymentsToUpdate;
                System.debug('Successfully updated ' + paymentsToUpdate.size() + ' Payment record(s)');
            } catch (DmlException dmlEx) {
                System.debug('ERROR updating Payment records: ' + dmlEx.getMessage());
            }
        }

        if (!logsToInsert.isEmpty()) {
            try {
                insert logsToInsert;
                System.debug('Successfully created ' + logsToInsert.size() + ' Event_Log__c record(s)');
            } catch (DmlException dmlEx) {
                System.debug('ERROR creating Event_Log__c records: ' + dmlEx.getMessage());
            }
        }

        System.debug('=== PAID Payment Create Queueable COMPLETE ===');
        System.debug('Total Payments Processed: ' + calloutResults.size());
        System.debug('Successful Creations: ' + successCount);
        System.debug('Failed Creations: ' + failureCount);
    }

    /**
    * @description Truncates error message to fit within field limits
    */
    private static String truncateErrorMessage(String errorMessage) {
        if (errorMessage == null) return null;

        Integer maxLength = 32768;
        if (errorMessage.length() <= maxLength) return errorMessage;

        return errorMessage.substring(0, maxLength - 15) + '...[TRUNCATED]';
    }
}