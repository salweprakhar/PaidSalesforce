global class PAIDRetryFailedSyncBatch
implements Database.Batchable<SObject>, Database.Stateful {

    /* Collected IDs */
    private Set<Id> orderIds     = new Set<Id>();
    private Set<Id> accountIds   = new Set<Id>();
    private Set<Id> contactIds   = new Set<Id>();
    private Set<Id> productIds   = new Set<Id>();
    private Set<Id> orderLineIds = new Set<Id>();

    /* ================= START ================= */
    global Database.QueryLocator start(Database.BatchableContext bc) {

        System.debug('=== PAID Retry Batch START ===');

        return Database.getQueryLocator([
            SELECT Id,
                   Operations_Key__c,
                   Account__c,
                   Contact__c,
                   Product__c,
                   Order__c,
                   Order_Number__c
            FROM Event_Log__c
            WHERE Success_Failure__c = 'Failure'
            AND CreatedDate = TODAY
        ]);
    }

    /* ================= EXECUTE ================= */
    global void execute(Database.BatchableContext bc, List<Event_Log__c> scope) {

        System.debug('Retry Batch Scope Size: ' + scope.size());

        for (Event_Log__c log : scope) {

            String op = log.Operations_Key__c;

            /* CUSTOMER */
            if (op == 'Create Customer' && log.Account__c != null && log.Order__c != null) {
                accountIds.add(log.Account__c);
                orderIds.add(log.Order__c);
            }

            /* CONTACT */
            else if (op == 'Create Contact' && log.Contact__c != null) {
                contactIds.add(log.Contact__c);
            }

            /* PRODUCT */
            else if (op == 'Update Product' && log.Product__c != null) {
                productIds.add(log.Product__c);
            }

            /* ORDER */
            else if (op == 'Create Order' && log.Order__c != null) {
                orderIds.add(log.Order__c);
            }

            /* ORDER LINE */
            else if (op == 'Create Order Line' && log.Order__c != null) {
                orderLineIds.add(log.Order__c);
            }
        }
    }

    /* ================= FINISH ================= */
    global void finish(Database.BatchableContext bc) {

        System.debug('=== PAID Retry Batch FINISH ===');
        System.debug('Accounts : ' + accountIds.size());
        System.debug('Contacts : ' + contactIds.size());
        System.debug('Products : ' + productIds.size());
        System.debug('Orders   : ' + orderIds.size());
        System.debug('OrderLines: ' + orderLineIds.size());

        /* ONLY ONE QUEUEABLE — GOVERNOR SAFE */
        if (
            !accountIds.isEmpty() ||
            !contactIds.isEmpty() ||
            !productIds.isEmpty() ||
            !orderIds.isEmpty() ||
            !orderLineIds.isEmpty()
        ) {
            System.enqueueJob(
                new PAIDRetryOrchestratorQueueable(
                    orderIds,
                    accountIds,
                    contactIds,
                    productIds,
                    orderLineIds
                )
            );
        }
    }
}