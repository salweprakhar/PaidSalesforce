/**
 * @description Queueable class to handle asynchronous contact creation in PAID
 * @author Manusha T 
 */
public class PAIDContactCreationQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Contact> contacts;
    private Map<Id, String> accountToPaidCustomerId;
    private Map<Id, Id> contactToOrderMap; // Map of Contact ID to Order ID
    
    /**
     * @description Constructor
     * @param contacts List of contacts to process
     * @param accountToPaidCustomerId Map of Account ID to PAID Customer External ID
     * @param contactToOrderMap Map of Contact ID to Order ID
     */
    public PAIDContactCreationQueueable(List<Contact> contacts, 
                                       Map<Id, String> accountToPaidCustomerId,
                                       Map<Id, Id> contactToOrderMap) {
        this.contacts = contacts;
        this.accountToPaidCustomerId = accountToPaidCustomerId;
        this.contactToOrderMap = contactToOrderMap;
    }
    
    /**
     * @description Execute method for Queueable
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        // List<Id> lstOrderIds=new List<Id>();
        // Get Contact IDs
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }
        
        // Get Order IDs
        Set<Id> orderIds = new Set<Id>(contactToOrderMap.values());
        
        // Query Contacts using helper
        List<SObject> contactRecords = PAIDHelper.queryRecordsWithMappings(
            'Contact', 
            'Contact_Creation', 
            contactIds,
            'PAID_Contact_Field_Mapping__mdt',null,null,null,null
        );
        
        // Convert to Contact Map
        Map<Id, Contact> contactMap = new Map<Id, Contact>();
        for (SObject record : contactRecords) {
            contactMap.put(record.Id, (Contact)record);
        }
        
        // Query Orders using helper
        List<Order> orders = (List<Order>)PAIDHelper.queryRecords(
            'Order',
            'Contact_Creation',
            orderIds
        );
        
        // Convert to Order Map
        Map<Id, Order> orderMap = new Map<Id, Order>();
        for (Order ord : orders) {
            orderMap.put(ord.Id, ord);
        }
        
        List<Contact> contactsToUpdate = new List<Contact>();
        List<Order> ordersToUpdate = new List<Order>();
        List<Event_Log__c> eventLogs = new List<Event_Log__c>();
        
        for (Contact con : contactMap.values()) {
            // Get related Order
            Id orderId = contactToOrderMap.get(con.Id);
            Order relatedOrder = orderMap.get(orderId);
            
            if (relatedOrder == null) {
                System.debug('No related Order found for Contact: ' + con.Id);
                continue;
            }
            
            // Get PAID Customer ID from Account
            String paidCustomerId = accountToPaidCustomerId.get(con.AccountId);
            
            if (String.isBlank(paidCustomerId)) {
                System.debug('No PAID Customer ID found for Contact: ' + con.Id);
                continue;
            }
            
            // Pre-callout validation
            PAIDContactCreationService.ValidationResult validationResult = 
                PAIDContactCreationService.validateContactData(con);
            
            if (!validationResult.isValid) {
                // Validation failed - update Order and log error
                relatedOrder.Sent_Contact_to_PAID__c = false;
                relatedOrder.PAID_Contact_Creation_Status__c = 'Failure';
                ordersToUpdate.add(relatedOrder);
                
                // Create event log for validation failure using PAIDHelper
                eventLogs.add(PAIDHelper.createEventLog(
                    'Create Contact',            // operationKey
                    null,                        // requestPayload
                    null,                        // responsePayload
                    false,                       // isSuccess
                    validationResult.errorMessage, // errorMessage
                    null,                        // accountId
                    con.Id,                      // contactId
                    relatedOrder.Id,             // orderId
                    null,                        //ProductId
                    relatedOrder.OrderNumber     // orderNumber
                ));
                continue;
            }
            
            // Mark as sent before callout
            relatedOrder.Sent_Contact_to_PAID__c = true;
            ordersToUpdate.add(relatedOrder);
            
            // Check if contact already exists in PAID - Sumanpreet
            Boolean isUpdate = String.isNotBlank(con.PAID_ContactExternalID__c);
            PAIDContactCreationService.PAIDCalloutResult calloutResult;
            
            if (isUpdate) {
                // UPDATE contact in PAID
                calloutResult =
                    PAIDContactCreationService.updateContactInPAID(con, paidCustomerId, con.PAID_ContactExternalID__c);
            } else {
                // CREATE contact in PAID
                calloutResult =
                    PAIDContactCreationService.createContactInPAID(con, paidCustomerId);
            }
          	
            // Make callout to PAID
            //PAIDContactCreationService.PAIDCalloutResult calloutResult = 
                //PAIDContactCreationService.createContactInPAID(con, paidCustomerId);
            
            // Handle response
            if (calloutResult.isSuccess) {
                // Success - update Order and Contact
                relatedOrder.PAID_Contact_Creation_Status__c = 'Success';
                // For CREATE → store new PAID Contact ID
                if (!isUpdate) {  			// Sumanpreet
                    relatedOrder.PAID_ContactExternalID__c = calloutResult.paidContactId;
                    con.PAID_ContactExternalID__c = calloutResult.paidContactId;
                    contactsToUpdate.add(con);
                }
                
               /* //List of Order Ids to trigger PAID Order API
                lstOrderIds.add(relatedOrder.Id);
				*/
                 // Create success event log using PAIDHelper
                eventLogs.add(PAIDHelper.createEventLog(
                    isUpdate ? 'Update Contact' : 'Create Contact',    // Sumanpreet
                    calloutResult.requestPayload,
                    calloutResult.responsePayload,
                    true,
                    null,
                    null,
                    con.Id,
                    relatedOrder.Id,
                    null,
                    relatedOrder.OrderNumber
                ));                
            } else {
                // Failure - update Order with failure status
                relatedOrder.PAID_Contact_Creation_Status__c = 'Failure';
                relatedOrder.PAID_ContactExternalID__c = null;
                
                // Create failure event log using PAIDHelper
                eventLogs.add(PAIDHelper.createEventLog(
                    isUpdate ? 'Update Contact' : 'Create Contact',   // Sumanpreet
                    calloutResult.requestPayload,
                    calloutResult.responsePayload,
                    false,
                    calloutResult.errorMessage,
                    null,
                    con.Id,
                    relatedOrder.Id,
                    null,
                    relatedOrder.OrderNumber
                ));
            }
        }
        
        // Perform DML operations
        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
        
        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
        
        if (!eventLogs.isEmpty()) {
            insert eventLogs;
        }
        /*//triggering PAID Order API after 
        if(!lstOrderIds.isEmpty()) {
            //system.enqueueJob(new PAIDOrderCreateQueueable(lstOrderIds));
        }*/
    }
}