public class ConsumptionRateTriggerHandler {

    public static void handleAfter(List<ConsumptionRate> rates) {
        Set<Id> consumptionScheduleIds = new Set<Id>();

        for (ConsumptionRate cr : rates) {
            if (cr.ConsumptionScheduleId != null) {
                consumptionScheduleIds.add(cr.ConsumptionScheduleId);
            }
        }

        if (consumptionScheduleIds.isEmpty()) return;

        // Get Product IDs via ProductConsumptionSchedule
        Set<Id> productIds = new Set<Id>();

        for (ProductConsumptionSchedule pcs : [
            SELECT ProductId
            FROM ProductConsumptionSchedule
            WHERE ConsumptionScheduleId IN :consumptionScheduleIds
        ]) {
            if (pcs.ProductId != null) {
                productIds.add(pcs.ProductId);
            }
        }

        if (!productIds.isEmpty()) {
            System.enqueueJob(
                new PAIDProductCreateQueueable(
                    new List<Id>(productIds)
                )
            );
        }
    }
}