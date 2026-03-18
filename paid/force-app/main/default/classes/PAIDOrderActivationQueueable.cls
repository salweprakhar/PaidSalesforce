public class PAIDOrderActivationQueueable implements Queueable, Database.AllowsCallouts {
    
    private Id orderId;
    private String paidOrderId;
    
    public PAIDOrderActivationQueueable(Id orderId, String paidOrderId) {
        this.orderId = orderId;
        this.paidOrderId = paidOrderId;
    }
    
    public void execute(QueueableContext context) {
        PAIDOrderItemService.activateOrderInPAID(paidOrderId, orderId);
    }
}