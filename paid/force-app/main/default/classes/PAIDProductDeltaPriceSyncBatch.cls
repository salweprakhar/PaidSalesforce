global class PAIDProductDeltaPriceSyncBatch
implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        System.debug('=== PAID Delta Batch START ===');

        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Product2
            WHERE IsActive = true
            AND PAID_ProductExternalID__c != null
            AND Id IN (
                SELECT Product2Id
                FROM PricebookEntry
                WHERE IsActive = true
                AND LastModifiedDate = TODAY
            )
        ]);
    }


    global void execute(Database.BatchableContext bc, List<Product2> scope) {

        System.debug('PAID Batch Chunk Size: ' + scope.size());

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : scope) productIds.add(p.Id);

        /* Latest price update per product */
        Map<Id, Datetime> productToPriceTime = new Map<Id, Datetime>();
        for (AggregateResult ar : [
            SELECT Product2Id pid, MAX(LastModifiedDate) lm
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND IsActive = true
            GROUP BY Product2Id
        ]) {
            productToPriceTime.put((Id) ar.get('pid'), (Datetime) ar.get('lm'));
        }

        /* Last successful PAID update today */
        Map<Id, Datetime> productToLastSync = new Map<Id, Datetime>();
        for (AggregateResult ar : [
            SELECT Product__c pid, MAX(CreatedDate) cd
            FROM Event_Log__c
            WHERE Product__c IN :productIds
            AND Operations_Key__c = 'Update Product'
            AND Success_Failure__c = 'Success'
            AND CreatedDate = TODAY
            GROUP BY Product__c
        ]) {
            productToLastSync.put((Id) ar.get('pid'), (Datetime) ar.get('cd'));
        }

        /* Collect only */
        List<Id> idsToSend = new List<Id>();

        for (Product2 p : scope) {

            Datetime priceTime = productToPriceTime.get(p.Id);
            Datetime lastSync  = productToLastSync.get(p.Id);

            if (lastSync == null || priceTime > lastSync) {
                System.debug('PAID Batch → Sending: ' + p.Name);
                idsToSend.add(p.Id);
            }
        }

        /* ONLY ACTION = QUEUEABLE */
        if (!idsToSend.isEmpty()) {
            System.enqueueJob(new PAIDProductUpdateQueueable(idsToSend));
        }
    }


    global void finish(Database.BatchableContext bc) {
        System.debug('=== PAID Delta Batch FINISHED ===');
    }
}