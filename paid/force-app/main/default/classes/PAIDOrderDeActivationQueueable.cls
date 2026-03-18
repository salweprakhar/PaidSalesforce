/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PAIDOrderDeActivationQueueable
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

public class PAIDOrderDeActivationQueueable implements Queueable, Database.AllowsCallouts  {
	private Id orderId;
    private String paidOrderId;
    
    public PAIDOrderDeActivationQueueable(Id orderId, String paidOrderId) {
        this.orderId = orderId;
        this.paidOrderId = paidOrderId;
    }
    
    public void execute(QueueableContext context) {
        PAIDOrderItemService.deactivateOrderInPAID(paidOrderId, orderId);
    }
}