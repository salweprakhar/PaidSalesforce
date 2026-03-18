public class ProductConsumptionScheduleTriggerHandler {

    public static void handleAfter(
        List<ProductConsumptionSchedule> records
    ) {
        Set<Id> productIds = new Set<Id>();

        for (ProductConsumptionSchedule pcs : records) {
            if (pcs.ProductId != null) {
                productIds.add(pcs.ProductId);
            }
        }

        if (!productIds.isEmpty()) {
            enqueuePaidUpdate(productIds);
        }
    }

    private static void enqueuePaidUpdate(Set<Id> productIds) {
        System.enqueueJob(
            new PAIDProductCreateQueueable(
                new List<Id>(productIds)
            )
        );
    }
}