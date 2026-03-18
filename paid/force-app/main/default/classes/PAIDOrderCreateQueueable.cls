public class PAIDOrderCreateQueueable  implements Queueable, Database.AllowsCallouts {
   private List<Id> orderIds;
      /**
     * @description Constructor
     * @param Order List of order Ids to create in PAID
     */
    public PAIDOrderCreateQueueable(List<Id> orderIds) {
        this.orderIds = orderIds;
    }
    /**
     * @description Executes the queueable job
     * @param context Queueable context
     */
    public void execute(QueueableContext context) {
        
        // Process each Order
        for (Id orderId : orderIds) {
            try {
                
                //PAIDOrderService.createUpdateOrder(orderId); 
                    PAIDOrdService.createUpdateOrder(orderId);
            } catch (Exception e) {
                System.debug('Error creating order in PAID: ' + e.getMessage());
                // Error handling is done in service class
            }
        }
    }
}