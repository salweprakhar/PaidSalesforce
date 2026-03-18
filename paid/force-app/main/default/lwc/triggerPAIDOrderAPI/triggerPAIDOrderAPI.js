import { LightningElement,api } from 'lwc';
import triggerPAIDOrderAPI from '@salesforce/apex/PAIDOrderService.triggerPAIDOrderAPI';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';

export default class TriggerPAIDOrderAPI extends LightningElement {
    @api recordId;

  @api invoke() {
        triggerPAIDOrderAPI({ orderId: this.recordId })
           .then(() => {
                this.showToast('Success', 'Action executed successfully', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                // Optional: Refresh the view after the action
                refreshApex(this.recordId); 
            })
            .catch(error => {
                this.showToast('Error', 'Error executing action: ' + error.body.message, 'error');
            })
    }
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}