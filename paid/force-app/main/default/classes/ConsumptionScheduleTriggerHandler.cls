/**
 * @description Handler for ConsumptionSchedule changes
 */
public class ConsumptionScheduleTriggerHandler {

    private static final String ChargeType = 'Recurring';

    // =========================
    // AFTER INSERT
    // =========================
    public void handleAfterInsert(List<ConsumptionSchedule> newSchedules) {
        queueAllUsageProducts('Insert');
    }

    // =========================
    // AFTER UPDATE
    // =========================
    public void handleAfterUpdate(
        List<ConsumptionSchedule> newSchedules,
        Map<Id, ConsumptionSchedule> oldMap
    ) {
        if (hasAnyRelevantChange(newSchedules, oldMap)) {
            queueAllUsageProducts('Update');
        }
    }

    // =========================
    // AFTER DELETE
    // =========================
    public void handleAfterDelete(List<ConsumptionSchedule> oldSchedules) {
        queueAllUsageProducts('Delete');
    }

    // =========================
    // AFTER UNDELETE
    // =========================
    public void handleAfterUndelete(List<ConsumptionSchedule> newSchedules) {
        queueAllUsageProducts('Undelete');
    }

    // =========================
    // CHANGE DETECTOR
    // =========================
    private Boolean hasAnyRelevantChange(
        List<ConsumptionSchedule> newSchedules,
        Map<Id, ConsumptionSchedule> oldMap
    ) {
        for (ConsumptionSchedule newCS : newSchedules) {
            ConsumptionSchedule oldCS = oldMap.get(newCS.Id);
            if (oldCS == null) continue;

            if (newCS.BillingTerm != oldCS.BillingTerm
                || newCS.BillingTermUnit != oldCS.BillingTermUnit
                || newCS.RatingMethod != oldCS.RatingMethod
                || newCS.UnitOfMeasure != oldCS.UnitOfMeasure
                || newCS.Type != oldCS.Type) {

                return true; // One change is enough
            }
        }
        return false;
    }

    // =========================
    // QUEUE PAID SYNC
    // =========================
    private void queueAllUsageProducts(String operation) {

        if (System.isBatch() || System.isFuture()) {
            System.debug('ConsumptionSchedule trigger skipped - batch/future');
            return;
        }

        List<Product2> products = [
            SELECT Id, Name, IsActive,
                   SBQQ__PricingMethod__c,
                   PAID_ProductExternalID__c,
                   Sent_UpdateProduct_to_PAID__c
            FROM Product2
          
        ];

        List<Id> productsToUpdate = new List<Id>();

        for (Product2 product : products) {

            // Must already exist in PAID
            if (String.isBlank(product.PAID_ProductExternalID__c)) {
                continue;
            }

            if (product.IsActive && !product.Sent_UpdateProduct_to_PAID__c) {
                productsToUpdate.add(product.Id);
            }
        }

        if (!productsToUpdate.isEmpty()) {
            System.enqueueJob(
                new PAIDProductUpdateQueueable(productsToUpdate)
            );
        }
    }
}