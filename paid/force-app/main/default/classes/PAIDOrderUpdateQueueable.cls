/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PAIDOrderUpdateQueueable
 * Author          : <YourName>
 * Created Date    : Mar 5, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 5, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 5, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class PAIDOrderUpdateQueueable implements Queueable, Database.AllowsCallouts {
	private List<Id> orderIds;
    public PAIDOrderUpdateQueueable(List<Id> orderIds) {
        this.orderIds = orderIds;
    }
    public void execute(QueueableContext context) {
        
        // Process each Order
        for (Id orderId : orderIds) {
            try {
                
                //PAIDOrderService.createUpdateOrder(orderId); 
                    //PAIDOrdService.createUpdateOrder(orderId);
            } catch (Exception e) {
                System.debug('Error creating order in PAID: ' + e.getMessage());
                // Error handling is done in service class
            }
        }
    }
}