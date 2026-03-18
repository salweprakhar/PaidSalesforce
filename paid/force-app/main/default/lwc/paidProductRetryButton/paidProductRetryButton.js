import { LightningElement, api } from 'lwc';
import retryProductSync from '@salesforce/apex/PAIDProductRetryController.retryProductSync';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class PaidProductRetryButton extends LightningElement {
    @api recordId;  // This will be Product2 Id

    @api invoke() {
        retryProductSync({ productId: this.recordId })
            .then(() => {
                this.showToast('Success', 'Product synced successfully to PAID', 'success');
                this.dispatchEvent(new CloseActionScreenEvent());
                setTimeout(() => {
                    // eslint-disable-next-line no-restricted-globals
                    location.reload();
                }, 1000);
            })
            .catch(error => {
                this.showToast('Error', 'Error syncing product: ' + error.body.message, 'error');
            });
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