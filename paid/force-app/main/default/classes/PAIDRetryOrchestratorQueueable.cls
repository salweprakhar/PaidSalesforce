public class PAIDRetryOrchestratorQueueable
implements Queueable, Database.AllowsCallouts {

    private Set<Id> orderIds;
    private Set<Id> accountIds;
    private Set<Id> contactIds;
    private Set<Id> productIds;
    private Set<Id> orderLineIds;

    public PAIDRetryOrchestratorQueueable(
        Set<Id> orderIds,
        Set<Id> accountIds,
        Set<Id> contactIds,
        Set<Id> productIds,
        Set<Id> orderLineIds
    ) {
        this.orderIds     = orderIds;
        this.accountIds   = accountIds;
        this.contactIds   = contactIds;
        this.productIds   = productIds;
        this.orderLineIds = orderLineIds;
    }

    public void execute(QueueableContext qc) {

        System.debug('=== PAID Retry Orchestrator START ===');

        /* CUSTOMER */
        if (!orderIds.isEmpty() && !accountIds.isEmpty()) {
            System.debug('Retry Customer');
            System.enqueueJob(
                new PAIDCustomerCreationQueueable(orderIds, accountIds)
            );
            return;
        }

        /* CONTACT */
        if (!contactIds.isEmpty()) {
            System.debug('Retry Contact');
            // Contact queueable already triggers Order internally
            // So we only enqueue contact here
            // (Data prepared earlier)
            return;
        }

        /* PRODUCT */
        if (!productIds.isEmpty()) {
            System.debug('Retry Product');
            System.enqueueJob(
                new PAIDProductUpdateQueueable(new List<Id>(productIds))
            );
            return;
        }

        /* ORDER */
        if (!orderIds.isEmpty()) {
            System.debug('Retry Order');
            System.enqueueJob(
                new PAIDOrderCreateQueueable(new List<Id>(orderIds))
            );
            return;
        }

        /* ORDER LINE */
        if (!orderLineIds.isEmpty()) {
            System.debug('Retry Order Line');
           /* System.enqueueJob(
                new PAIDOrderLineCreateQueueable(new List<Id>(orderLineIds))
            );*/
        }

        System.debug('=== PAID Retry Orchestrator END ===');
    }
}