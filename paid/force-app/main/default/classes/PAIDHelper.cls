/**
* @description Helper class for dynamic SOQL queries using Custom Metadata
* @author Manusha T
*/
public class PAIDHelper {
    
    private static Map<String, PAID_API_Configuration__mdt> apiConfigCache = 
        new Map<String, PAID_API_Configuration__mdt>();
    private static Map<String, List<SObject>> fieldMappingsCache = 
        new Map<String, List<SObject>>();
    
    public static PAID_API_Configuration__mdt getAPIConfiguration(String operationType) {
        if (apiConfigCache.containsKey(operationType)) {
            return apiConfigCache.get(operationType);
        }
        
        List<PAID_API_Configuration__mdt> configs = [
            SELECT Endpoint_Path__c, HTTP_Method__c, 
            Named_Credential__c, Content_Type__c 
            FROM PAID_API_Configuration__mdt
            WHERE Active__c = true
            AND Operation_Type__c = :operationType
            LIMIT 1
        ];
        
        if (configs.isEmpty()) {
            throw new PAIDIntegrationException(
                'No active API configuration found for operation: ' + operationType
            );
        }
        
        PAID_API_Configuration__mdt config = configs[0];
        apiConfigCache.put(operationType, config);
        
        return config;
    }
    
    public static List<SObject> getFieldMappings(String fieldMappingType, String objectName) {
        String cacheKey = fieldMappingType + '_' + objectName;
        String soql;
        
        if (fieldMappingsCache.containsKey(cacheKey)) {
            return fieldMappingsCache.get(cacheKey);
        }
        
        if(objectName != null){
            soql = 'SELECT Salesforce_Object__c, Salesforce_Field_API_Name__c, Active__c,' +
                'PAID_Field_Name__c, Data_Type__c, Is_Required__c,Operation_Type__c, ' +
                'Parent_Field__c, Default_Value__c, Transformation_Rule__c, Sequence__c ' +
                'FROM ' + fieldMappingType + ' ' +
                'WHERE Active__c = true ' +
                'AND Salesforce_Object__c = :objectName ' +
                'ORDER BY Sequence__c ASC';
        }else{
            soql = 'SELECT Salesforce_Object__c,MasterLabel, Salesforce_Field_API_Name__c, Active__c,' +
                'PAID_Field_Name__c, Data_Type__c, Is_Required__c,Operation_Type__c, ' +
                'Parent_Field__c, Default_Value__c, Transformation_Rule__c, Sequence__c ' +
                'FROM ' + fieldMappingType + ' ' +
                'WHERE Active__c = true ' +
                'ORDER BY Sequence__c ASC';
        }
        
        List<SObject> mappings = Database.query(soql);
        
        fieldMappingsCache.put(cacheKey, mappings);
        
        return mappings;
    }
    
    
    public static List<SObject> queryRecord(String objectName,String integrationType,Set<Id> recordIds,String whereClause,String bindVarName,Object bindVarValue) {
        
        List<PAID_Base_Query_Fields__mdt> baseFieldsConfigs = [
            SELECT Base_Fields__c
            FROM PAID_Base_Query_Fields__mdt
            WHERE Object_API_Name__c = :objectName
            AND Integration_Type__c = :integrationType
            AND Active__c = true
            LIMIT 1
        ];
        
        if (baseFieldsConfigs.isEmpty()) {
            throw new PAIDIntegrationException(
                'No query configuration found for object: ' + objectName + 
                ', integration: ' + integrationType
            );
        }  
        
        PAID_Base_Query_Fields__mdt baseFieldsConfig = baseFieldsConfigs[0];
        
        Set<String> fieldsToQuery = new Set<String>();
        
        if (baseFieldsConfig != null && String.isNotBlank(baseFieldsConfig.Base_Fields__c)) {
            for (String field : baseFieldsConfig.Base_Fields__c.split(',')) {
                String trimmedField = field.trim();
                if (String.isNotBlank(trimmedField)) {
                    fieldsToQuery.add(trimmedField);
                }
            }
        }
        
        if (fieldsToQuery.isEmpty()) {
            throw new PAIDIntegrationException(
                'No fields configured for object: ' + objectName + 
                ', integration: ' + integrationType
            );
        }
        
        String soql = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') + 
            ' FROM ' + objectName;
        
        if (String.isNotBlank(whereClause)) {
            if (bindVarName == 'orderId') {
                Id orderId = (Id)bindVarValue;
                soql += ' WHERE OrderId = :orderId';
            } else {
                soql += ' WHERE ' + whereClause;
            }
        } else if (recordIds != null && !recordIds.isEmpty()) {
            soql += ' WHERE Id IN :recordIds';
        } else {
            return new List<SObject>();
        }
        
        System.debug('Dynamic SOQL for ' + objectName + ': ' + soql);
        
        return Database.query(soql);
    }
    
    public static List<SObject> queryRecords(String objectName, String integrationType, Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<SObject>();
        }
        return queryRecord(objectName, integrationType, recordIds, null, null, null);
    }
    
    
    public static List<SObject> queryRecordsWithMappings(
        String objectName,
        String integrationType,
        Set<Id> recordIds,
        String fieldMappingType,
        String whereClause,
        String bindVarName,
        Object bindVarValue,
        String orderByClause
    ) {
        Id productId;
        Id orderId;
        Id accountId;
        
        if (recordIds == null && String.isBlank(whereClause) && String.isBlank(bindVarName)) {
            return new List<SObject>();
        }
        
        List<PAID_Base_Query_Fields__mdt> baseFieldsConfigs = [
            SELECT Base_Fields__c
            FROM PAID_Base_Query_Fields__mdt
            WHERE Object_API_Name__c = :objectName
            AND Integration_Type__c = :integrationType
            AND Active__c = true
            LIMIT 1
        ];
        
        if (baseFieldsConfigs.isEmpty()) {
            throw new PAIDIntegrationException(
                'No query configuration found for object: ' + objectName + 
                ', integration: ' + integrationType
            );
        }
        
        PAID_Base_Query_Fields__mdt baseFieldsConfig = baseFieldsConfigs[0];
        
        Set<String> fieldsToQuery = new Set<String>();
        
        if (baseFieldsConfig != null && String.isNotBlank(baseFieldsConfig.Base_Fields__c)) {
            for (String field : baseFieldsConfig.Base_Fields__c.split(',')) {
                String trimmedField = field.trim();
                if (String.isNotBlank(trimmedField)) {
                    fieldsToQuery.add(trimmedField);
                }
            }
        }
        
        if (String.isNotBlank(fieldMappingType)) {
            String mappingSoql = 'SELECT Salesforce_Field_API_Name__c FROM ' + fieldMappingType + 
                ' WHERE Active__c = true AND Salesforce_Object__c = :objectName';
            
            try {
                List<SObject> fieldMappings = Database.query(mappingSoql);
                for (SObject mapping : fieldMappings) {
                    String fieldName = (String)mapping.get('Salesforce_Field_API_Name__c');
                    if (String.isNotBlank(fieldName)) {
                        fieldsToQuery.add(fieldName.trim());
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying field mappings: ' + e.getMessage());
            }
        }
        
        if (fieldsToQuery.isEmpty()) {
            throw new PAIDIntegrationException(
                'No fields configured for object: ' + objectName + 
                ', integration: ' + integrationType
            );
        }
        
        String soql = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') + 
            ' FROM ' + objectName;
        
        if (recordIds != null && !recordIds.isEmpty()) {
            soql += ' WHERE Id IN :recordIds';
        } else if (String.isNotBlank(bindVarName)) {
            if (bindVarName == 'orderId') {
                orderId = (Id)bindVarValue;
                soql += ' WHERE OrderId = :orderId';
            } else if (bindVarName == 'accountId') {
                accountId = (Id)bindVarValue;
                soql += ' WHERE AccountId = :accountId';
            } else if (bindVarName == 'productId') {
                productId = (Id)bindVarValue;
                
                if (objectName == 'PricebookEntry') {
                    soql += ' WHERE Product2Id = :productId AND IsActive = true';
                } else if (objectName == 'SBQQ__BlockPrice__c' || objectName == 'SBQQ__Cost__c') {
                    soql += ' WHERE SBQQ__Product__c = :productId';
                } else if (objectName == 'Product2') {
                    soql += ' WHERE Id = :productId';
                } else {
                    soql += ' WHERE Product2Id = :productId';
                }
            } else {
                soql += ' WHERE ' + whereClause;
            }
        } else if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        
        if (String.isNotBlank(orderByClause)) {
            soql += ' ORDER BY ' + orderByClause;
        }
        
        System.debug('***** Dynamic SOQL for ' + objectName + ' with mappings: ' + soql);
        
        return Database.query(soql);
    }
    
    public static Map<Id, SObject> toMap(List<SObject> records) {
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        if (records != null) {
            for (SObject record : records) {
                recordMap.put(record.Id, record);
            }
        }
        return recordMap;
    }
    
    public static Event_Log__c createEventLog(
        String operationKey,
        String requestPayload,
        String responsePayload,
        Boolean isSuccess,
        String errorMessage, 
        Id accountId,
        Id contactId,
        Id orderId,
        Id ProductId,
        String orderNumber
    ) {
        Event_Log__c log = new Event_Log__c();
        log.Operations_Key__c = operationKey;
        log.Request_Payload__c = requestPayload;
        log.Response_Payload__c = responsePayload;
        log.Success_Failure__c = isSuccess ? 'Success' : 'Failure';
        log.Error_Message__c = errorMessage;
        
        if (accountId != null) { 
            log.Account__c = accountId;
        }
        if (contactId != null) {
            log.Contact__c = contactId;
        }
        if (orderId != null) {
            log.Order__c = orderId;
        }
        if (String.isNotBlank(orderNumber)) {
            log.Order_Number__c = orderNumber;
        }
        if (ProductId != null) {
            log.Product__c = ProductId;
        }
        
        return log;
    }
    
    public static Object applyTransformation(Object fieldValue, String transformationRule) {
        if (fieldValue == null || String.isBlank(transformationRule) || transformationRule == 'None') {
            return fieldValue;
        }
        
        
        if (transformationRule == 'Uppercase' || transformationRule == 'ToUpperCase') {
            String strValue = String.valueOf(fieldValue);
            return strValue.toUpperCase();
        }
        
        if (transformationRule == 'Lowercase' || transformationRule == 'ToLowerCase') {
            String strValue = String.valueOf(fieldValue);
            return strValue.toLowerCase();
        }
        
        if (transformationRule == 'ChargeTypeMapping') {
            String stringValue = String.valueOf(fieldValue);
            if (stringValue == 'Recurring') {
                return 'seatBased';
            } else if (stringValue == 'One-Time') {
                return 'oneTime';
            } else if (stringValue == 'Usage') {
                return 'usage';
            }
            return stringValue;
            
        }
        if (transformationRule == 'PricingModelMapping') {
            String stringValue = String.valueOf(fieldValue);
            if (stringValue == 'List' || stringValue == 'Cost' || stringValue == 'Percent of Total') {
                return 'PerUnit';
            } else if (stringValue == 'Block') {
                return 'GraduatedPricing';
            }
            return 'PerUnit';
        }
        
        if (transformationRule == 'CurrencyDefault') {
            String stringValue = String.valueOf(fieldValue);
            return String.isBlank(stringValue) ? 'USD' : stringValue;
            
        }
        
        if (transformationRule == 'Trim' || transformationRule == 'TrimWhitespace') {
            String strValue = String.valueOf(fieldValue);
            return strValue.trim();
        }
        
        if (transformationRule == 'Format_Phone' || transformationRule == 'Format Phone') {
            String strValue = String.valueOf(fieldValue);
            return strValue.replaceAll('[^0-9]', '');
        }
        
        if (transformationRule == 'RemoveSpaces') {
            String strValue = String.valueOf(fieldValue);
            return strValue.deleteWhitespace();
        }
        
        if (transformationRule == 'DateToString') {
            if (fieldValue instanceof Date) {
                return ((Date)fieldValue).format();
            } else if (fieldValue instanceof Datetime) {
                return ((Datetime)fieldValue).format('yyyy-MM-dd');
            }
            return fieldValue;
        }
        
        if (transformationRule == 'DateTimeToString') {
            if (fieldValue instanceof Datetime) {
                return ((Datetime)fieldValue).format('yyyy-MM-dd HH:mm:ss');
            }
            return fieldValue;
        }
        
        if (transformationRule == 'DateToISODateTime') {
            if (fieldValue instanceof Date) {
                Date d = (Date)fieldValue;
                Datetime dt = Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0);
                return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            } else if (fieldValue instanceof Datetime) {
                return ((Datetime)fieldValue).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            }
            return fieldValue;
        }
        
        if (transformationRule == 'BooleanToString') {
            if (fieldValue instanceof Boolean) {
                return String.valueOf(fieldValue);
            }
            return fieldValue;
        }
        
        if (transformationRule == 'MultiplyBy100') {
            if (fieldValue instanceof Decimal) {
                return ((Decimal)fieldValue) * 100;
            } else if (fieldValue instanceof Double) {
                return ((Double)fieldValue) * 100;
            } else if (fieldValue instanceof Integer) {
                return ((Integer)fieldValue) * 100;
            }
            return fieldValue;
        }
        
        if (transformationRule == 'DivideBy100') {
            if (fieldValue instanceof Decimal) {
                return ((Decimal)fieldValue) / 100;
            } else if (fieldValue instanceof Double) {
                return ((Double)fieldValue) / 100;
            } else if (fieldValue instanceof Integer) {
                return ((Integer)fieldValue) / 100.0;
            }
            return fieldValue;
        }
        
        return fieldValue;
    }
    
    
    public static Object convertDataType(Object fieldValue, String dataType) {
        if (fieldValue == null || String.isBlank(dataType)) {
            return fieldValue;
        }
        
        try {
            
            if (dataType == 'String' || dataType == 'Text') {
                return String.valueOf(fieldValue);
            }
            
            if (dataType == 'Integer' || dataType == 'Number') {
                if (fieldValue instanceof Integer) {
                    return fieldValue;
                } else if (fieldValue instanceof Decimal) {
                    return ((Decimal)fieldValue).intValue();
                } else if (fieldValue instanceof Double) {
                    return ((Double)fieldValue).intValue();
                } else {
                    return Integer.valueOf(String.valueOf(fieldValue));
                }
            }
            
            if (dataType == 'Decimal') {
                if (fieldValue instanceof Decimal) {
                    return fieldValue;
                } else if (fieldValue instanceof Integer) {
                    return Decimal.valueOf((Integer)fieldValue);
                } else if (fieldValue instanceof Double) {
                    return Decimal.valueOf((Double)fieldValue);
                } else {
                    return Decimal.valueOf(String.valueOf(fieldValue));
                }
            }
            
            if (dataType == 'Double') {
                if (fieldValue instanceof Decimal) {
                    return fieldValue;
                } else if (fieldValue instanceof Double) {
                    return fieldValue;
                } else {
                    return Decimal.valueOf(String.valueOf(fieldValue));
                }
            }
            
            if (dataType == 'Boolean') {
                if (fieldValue instanceof Boolean) {
                    return fieldValue;
                }
                return Boolean.valueOf(String.valueOf(fieldValue));
            }
            
            if (dataType == 'Date') {
                if (fieldValue instanceof Date) {
                    return fieldValue;
                } else if (fieldValue instanceof DateTime) {
                    return ((DateTime)fieldValue).date();
                } else {
                    return Date.valueOf(String.valueOf(fieldValue));
                }
            }
            
            if (dataType == 'DateTime') {
                if (fieldValue instanceof DateTime) {
                    return fieldValue;
                } else if (fieldValue instanceof Date) {
                    return DateTime.newInstance((Date)fieldValue, Time.newInstance(0, 0, 0, 0));
                } else {
                    return DateTime.valueOf(String.valueOf(fieldValue));
                }
            }
            
            return fieldValue;
            
        } catch (Exception e) {
            System.debug('Error converting data type: ' + e.getMessage());
            return fieldValue;
        }
    }
    
    public class PAIDIntegrationException extends Exception {}
}