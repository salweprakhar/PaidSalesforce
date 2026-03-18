public class PAIDOrderItemCreationQueueable implements Queueable, Database.AllowsCallouts {
    
    private Id orderId;
    private String paidOrderId;
    private String contextType;
    
    public PAIDOrderItemCreationQueueable(Id orderId, String paidOrderId,string contextType ) {
        this.orderId = orderId;
        this.paidOrderId = paidOrderId;
        this.contextType = contextType;
    }
    
    public void execute(QueueableContext context) {
        PAIDOrderItemService.createOrderItems(orderId, paidOrderId,contextType);
    }
}