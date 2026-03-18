/**
 * @description Handler class for Order trigger - manages PAID integration logic
 * @author Manusha T 
 */
public class OrderTriggerHandler {
    
    public static Boolean isOrderPAIDTriggered=false;

    /**
 * @description Populate External IDs on Order from related Account and Contact
 * @param orders List of Order records
 */
public static void populateExternalIds(List<Order> orders) {
    // Collect Account and Contact IDs
    Set<Id> accountIds = new Set<Id>();
    Set<Id> contactIds = new Set<Id>();
    
    for (Order ord : orders) {
        if (ord.AccountId != null) {
            accountIds.add(ord.AccountId);
        }
        if (ord.BillToContactId != null) { 
            contactIds.add(ord.BillToContactId);
        }
    }
    
    // Query Accounts with External IDs
    Map<Id, Account> accountMap = new Map<Id, Account>();
    if (!accountIds.isEmpty()) {
        List<Account> accountRecords = PAIDHelper.queryRecords(
            'Account',
            'Customer_Creation',  
            accountIds
        );
        for (Account acc : accountRecords) {
            accountMap.put(acc.Id, acc);
        }
    }
    
    // Query Contacts with External IDs
    Map<Id, Contact> contactMap = new Map<Id, Contact>();
    if (!contactIds.isEmpty()) {
        List<Contact> contactRecords = PAIDHelper.queryRecords(
            'Contact', 
            'Contact_Creation',  
            contactIds
        );
        
        for (Contact con : contactRecords) {
            contactMap.put(con.Id, con);
        }
    }
    
    // Populate External IDs on Orders
    for (Order ord : orders) {
        // Populate Customer External ID from Account
        if (ord.AccountId != null && accountMap.containsKey(ord.AccountId)) {
            Account relatedAccount = accountMap.get(ord.AccountId);
            if (String.isNotBlank(relatedAccount.PAID_CustomerExternalID__c)) {
                ord.PAID_CustomerExternalID__c = relatedAccount.PAID_CustomerExternalID__c;
            }
        }
        
        // Populate Contact External ID from Contact
        if (ord.BillToContactId != null && contactMap.containsKey(ord.BillToContactId)) {
            Contact relatedContact = contactMap.get(ord.BillToContactId);
            if (String.isNotBlank(relatedContact.PAID_ContactExternalID__c)) {
                ord.PAID_ContactExternalID__c = relatedContact.PAID_ContactExternalID__c;
            }
        }
    }
    
    System.debug('Populated External IDs on Orders');
}
    
    /**
     * @description Handles after update trigger logic
     * @param newOrders List of new Order records
     * @param oldOrderMap Map of old Order records
     */
    public static void handleAfterUpdate(List<Order> newOrders, Map<Id, Order> oldOrderMap) {
        List<Order> ordersToProcess = new List<Order>();
        Set<Id> lstOrderIds=new Set<Id>();
        Map<Id, Order> mapOfOrder = new Map<Id, Order>();
        // Identify orders that just became Active and haven't sent customer data yet
        for (Order newOrder : newOrders) {
            Order oldOrder = oldOrderMap.get(newOrder.Id);
           
            // Check if Order status changed to Active
            System.debug('newOrder.Status ::'+newOrder.Status);
			System.debug('oldOrder.Status ::'+oldOrder.Status);
			System.debug('String.isBlank(newOrder.PAID_CustomerExternalID__c) '+String.isBlank(newOrder.PAID_CustomerExternalID__c)); 
            System.debug('String.isBlank(newOrder.PAID_ContactExternalID__c '+String.isBlank(newOrder.PAID_ContactExternalID__c)); 
            if (newOrder.Status == 'Activated' && 
                oldOrder.Status != 'Activated' &&
                (String.isBlank(newOrder.PAID_CustomerExternalID__c) || 
                 String.isBlank(newOrder.PAID_ContactExternalID__c))) {
                               System.debug('Check ordersToProcess:::');
                ordersToProcess.add(newOrder);
            }
            
            if (newOrder.Status == 'Activated' 
                && !newOrder.Sent_To_Paid__c &&
                String.isNotBlank(newOrder.PAID_CustomerExternalID__c) &&
                String.isBlank(newOrder.BillToContactId)){
                lstOrderIds.add(newOrder.Id);
            }
            if (newOrder.Status == 'Activated' 
                && !newOrder.Sent_To_Paid__c &&
                String.isNotBlank(newOrder.PAID_CustomerExternalID__c) &&
                String.isNotBlank(newOrder.PAID_ContactExternalID__c)){
                lstOrderIds.add(newOrder.Id);
            }
            if(newOrder.Status == 'Draft' && String.isNotBlank(newOrder.PAID_Order_ID__c) && newOrder.Status != oldOrder.Status){
                System.enqueueJob(new PAIDOrderDeActivationQueueable(newOrder.Id, newOrder.PAID_Order_ID__c));
            }if(newOrder.Status != 'Activated'){
                lstOrderIds.add(newOrder.Id);
            }
            mapOfOrder.put(newOrder.Id, newOrder);
        }
        
        System.debug('ordersToProcess:::'+ordersToProcess);
        
        if (!ordersToProcess.isEmpty()) {
            System.debug('ordersToProcess not Empty::'+ordersToProcess);
            processOrdersForPAID(ordersToProcess);
        }
         //triggering PAID Order API when  customer  already exist
        if(!lstOrderIds.isEmpty() && !isOrderPAIDTriggered) {
            System.debug('lstOrderIds not Empty::'+lstOrderIds);
            isOrderPAIDTriggered=true;
            System.enqueueJob(new PAIDOrderCreateQueueable(new List<Id>(lstOrderIds)));
            
            
        }
    }
    
    /**
     * @description Process orders for PAID customer creation
     * @param orders List of orders to process
     */
    private static void processOrdersForPAID(List<Order> orders) {
        System.debug('processOrdersForPAID entered in to this method');
        // Get related Account data
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        List<Id> lstOrderIds=new List<Id>();
        
        for (Order ord : orders) {
            if (ord.AccountId != null) {
                accountIds.add(ord.AccountId);
            }
            
            if (ord.BillToContactId != null) {
                contactIds.add(ord.BillToContactId);
            }
        }
        
        System.debug('accountIds:::'+accountIds);
        
        if (accountIds.isEmpty()) {
            return;
        }
        
        // Query Accounts using helper
        List<SObject> accountRecords = PAIDHelper.queryRecordsWithMappings(
            'Account', 
            'Customer_Creation', 
            accountIds,
            'PAID_Customer_Field_Mapping__mdt',null,null,null,null
        );
        
        // Convert to Account Map
        Map<Id, Account> accountMap = new Map<Id, Account>();
        for (SObject record : accountRecords) {
            accountMap.put(record.Id, (Account)record);
        }
        
         Map<Id, Contact> contactMap = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            List<SObject> contactRecords = PAIDHelper.queryRecords(
                'Contact',
                'Contact_Creation',
                contactIds
            );
            
            for (SObject record : contactRecords) {
                contactMap.put(record.Id, (Contact)record);
            }
        }
        
        System.debug('accountMap:::'+accountMap);
        System.debug('contactMap:::'+contactMap);
        
        // Filter orders that need customer creation
        List<Order> ordersNeedingCustomerCreation = new List<Order>();
        List<Order> ordersWithExistingCustomer = new List<Order>();
        
        for (Order ord : orders) {
            Account relatedAccount = accountMap.get(ord.AccountId);
            Contact relatedContact = contactMap.get(ord.BillToContactId);
            
            System.debug('relatedAccount:::'+relatedAccount);
            System.debug('relatedAccount.PAID_CustomerExternalID__c:::'+relatedAccount.PAID_CustomerExternalID__c);
             System.debug('relatedContact:::'+relatedContact);
            System.debug('relatedContact.PAID_ContactExternalID__c:::'+relatedContact?.PAID_ContactExternalID__c);
            
            // Only proceed if Account doesn't have PAID Customer External ID
            if (relatedAccount != null){ 
                if(String.isBlank(relatedAccount.PAID_CustomerExternalID__c)) {
                    System.debug('Needs customer creation');
                    ordersNeedingCustomerCreation.add(ord);
                }else if (relatedContact != null && 
                          String.isBlank(relatedContact.PAID_ContactExternalID__c)) {
                    // Account already has customer ID AND Contact needs to be created
                    System.debug('Customer exists, but contact needs creation');
                    ordersWithExistingCustomer.add(ord);
                } else {
                    // Both customer and contact already exist - nothing to do
                    System.debug('Both customer and contact already exist');
                     //triggering PAID Order API
                    lstOrderIds.add(ord.Id);
                }
            }
        }

        System.debug('ordersNeedingCustomerCreation::::'+ordersNeedingCustomerCreation);
        System.debug('ordersWithExistingCustomer::::'+ordersWithExistingCustomer);

        if (!ordersNeedingCustomerCreation.isEmpty()) {
            System.debug('About to call customer creation queue');
            Set<Id> orderIds = new Map<Id, Order>(ordersNeedingCustomerCreation).keySet();
            Set<Id> accountIdsForCustomerCreation = new Set<Id>();
            for (Order ord : ordersNeedingCustomerCreation) {
                accountIdsForCustomerCreation.add(ord.AccountId);
            }
            System.enqueueJob(new PAIDCustomerCreationQueueable(orderIds, accountIdsForCustomerCreation));
        }
        
        //Directly trigger contact creation for orders with existing customers
        if (!ordersWithExistingCustomer.isEmpty()) {
            System.debug('About to trigger contact creation directly');
            triggerContactCreationDirectly(ordersWithExistingCustomer, accountMap);
        }

        System.debug('lstOrderIds :: '+lstOrderIds);
        System.debug('isOrderPAIDTriggered :: '+isOrderPAIDTriggered);
        //triggering PAID Order API when Both customer and contact already exist
        if(!lstOrderIds.isEmpty() && !isOrderPAIDTriggered) {
            isOrderPAIDTriggered=true;
            System.debug('OrderTriggerHandler 237 :: ');
            system.enqueueJob(new PAIDOrderCreateQueueable(lstOrderIds));
        }
    }
    
     /**
     * @description Trigger contact creation directly when customer already exists
     * @param orders List of orders with existing customers
     * @param accountMap Map of all accounts
     */
    private static void triggerContactCreationDirectly(List<Order> orders, Map<Id, Account> accountMap) {
        // Build map of AccountId to PAID_CustomerExternalID
        Map<Id, String> accountToPaidCustomerId = new Map<Id, String>();
        
        for (Order ord : orders) {
            Account acc = accountMap.get(ord.AccountId);
            if (acc != null && String.isNotBlank(acc.PAID_CustomerExternalID__c)) {
                accountToPaidCustomerId.put(acc.Id, acc.PAID_CustomerExternalID__c);
            }
        }
        
        if (accountToPaidCustomerId.isEmpty()) {
            System.debug('No accounts with PAID Customer IDs found');
            return;
        }
        
        // Collect BillToContact IDs from Orders
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Id> contactToOrderMap = new Map<Id, Id>(); // Contact ID -> Order ID
        
        for (Order ord : orders) {
            if (ord.BillToContactId != null && 
                accountToPaidCustomerId.containsKey(ord.AccountId)) {
                contactIds.add(ord.BillToContactId);
                contactToOrderMap.put(ord.BillToContactId, ord.Id);
            }
        }
        
        if (contactIds.isEmpty()) {
            System.debug('No BillToContacts found for contact creation');
            return;
        }
        
        // Query Contacts using helper
        List<SObject> contactRecords = PAIDHelper.queryRecordsWithMappings(
            'Contact', 
            'Contact_Creation', 
            contactIds,
            'PAID_Contact_Field_Mapping__mdt',null,null,null,null
        );
        
        // Filter contacts that haven't been sent to PAID yet
        List<Contact> eligibleContacts = new List<Contact>();
        for (SObject record : contactRecords) {
            Contact con = (Contact)record;
            
            // Only process if Contact doesn't have PAID External ID
            if (String.isBlank(con.PAID_ContactExternalID__c) &&
                accountToPaidCustomerId.containsKey(con.AccountId)) {
                eligibleContacts.add(con);
            }
        }
        
        if (!eligibleContacts.isEmpty()) {
            System.debug('Triggering Contact Creation for ' + eligibleContacts.size() + ' contacts');
            
            // Enqueue Contact Creation job
            System.enqueueJob(new PAIDContactCreationQueueable(
                eligibleContacts, 
                accountToPaidCustomerId,
                contactToOrderMap
            ));
        } else {
            System.debug('No eligible contacts found for PAID creation');
        }
    }    
}