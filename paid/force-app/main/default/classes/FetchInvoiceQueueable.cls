public class FetchInvoiceQueueable implements Queueable, Database.AllowsCallouts {

    private Id orderId;
    private Integer retryCount;

    public FetchInvoiceQueueable(Id orderId, Integer retryCount) {
        this.orderId = orderId;
        this.retryCount = retryCount;
    }

    public void execute(QueueableContext context) {

        Order ord = [
            SELECT Id, PAID_Order_Id__c, PAID_CustomerExternalID__c, PAID_Invoice_Id__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        String paidOrderId = ord.PAID_Order_Id__c;
        String customerId = ord.PAID_CustomerExternalID__c;

        PAID_API_Configuration__mdt config =
            PAID_API_Configuration__mdt.getInstance('Get_Invoices');

        try {

            String endpoint =
                'callout:' + config.Named_Credential__c +
                config.Endpoint_Path__c +
                '?customerId=' + customerId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod(config.HTTP_Method__c);

            HttpResponse res = new Http().send(req);

            Map<String,Object> response =
                (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

            List<Object> invoices =
                (List<Object>)response.get('data');

            String invoiceId;

            if(invoices != null){

                for(Object obj : invoices){

                    Map<String,Object> inv =
                        (Map<String,Object>)obj;

                    String orderIdFromInvoice =
                        (String)inv.get('orderId');

                    if(orderIdFromInvoice == paidOrderId){

                        invoiceId = (String)inv.get('id');
                        break;
                    }
                }
            }

            if(invoiceId != null){

                ord.PAID_Invoice_Id__c = invoiceId;
                update ord;

                System.debug('Invoice stored: ' + invoiceId);

            } else if(retryCount < 2){

                System.debug('Invoice not found yet. Retrying...');

                System.enqueueJob(
                    new FetchInvoiceQueueable(orderId, retryCount + 1)
                );
            }

        } catch(Exception e) {

            System.debug('Invoice fetch error: ' + e.getMessage());

        }
    }
}