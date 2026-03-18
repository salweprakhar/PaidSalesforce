global class PAIDProductDeltaPriceSyncScheduler
implements Schedulable {

    global void execute(SchedulableContext sc) {

        PaidAI_Product_Config__mdt cfg =
            PaidAI_Product_Config__mdt.getInstance('Default');

        Integer size = (cfg != null && cfg.Batch_Size__c != null)
            ? Integer.valueOf(cfg.Batch_Size__c)
            : 50;

        Database.executeBatch(new PAIDProductDeltaPriceSyncBatch(), size);
    }
}