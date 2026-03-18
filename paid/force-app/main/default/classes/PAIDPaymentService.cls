public class PAIDPaymentService {
    /**
    * @description Service class for PAID Payment API operations
    * @author Himanshu
    * @date 2026
    */

    private static final String CREATE_OPERATION = 'Create';
    private static final String UPDATE_OPERATION = 'Update';
    private static final String PAYMENT_SYNC_INTEGRATION = 'Payment_Sync';

    /**
    * @description Performs ONLY the HTTP callout for payment creation - NO DML
    */
    public static CalloutResult createPaymentCalloutOnly(Id paymentId) {
        CalloutResult result = new CalloutResult();
        result.paymentId = paymentId;

        System.debug('=== START CREATE Payment CALLOUT ONLY ===');
        System.debug('Payment ID: ' + paymentId);

        try {
            // Get configuration
            PAID_API_Configuration__mdt config = getAPIConfiguration(CREATE_OPERATION);
            if (config == null) {
                throw new PAIDPaymentException('No active API configuration found for Payment Creation');
            }

            

            // TODO: Build request payload
            String requestBody = '{}'; // Replace with real payload builder
            result.requestBody = requestBody;

            System.debug('****** Request Body : ' + result.requestBody);

            // Make HTTP callout
            HttpResponse response = makeCallout(config, result.requestBody, null);

            result.statusCode = response.getStatusCode();
            result.responseBody = response.getBody();
            result.success = (result.statusCode >= 200 && result.statusCode < 300);

            if (result.success) {
                try {
                    Map<String, Object> responseMap =
                        (Map<String, Object>) JSON.deserializeUntyped(result.responseBody);
                    result.paidExternalId = extractPaymentId(responseMap);
                } catch (Exception e) {
                    result.success = false;
                    result.errorMessage = 'Failed to extract Payment ID from response: ' + e.getMessage();
                }
            } else {
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + result.responseBody;
            }

            System.debug('=== END CREATE PAYMENT CALLOUT - ' + (result.success ? 'SUCCESS' : 'FAILURE') + ' ===');

        } catch (PAIDPaymentException integEx) {
            result.success = false;
            result.errorMessage = 'Integration error: ' + integEx.getMessage();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';

        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + ex.getMessage() + ' | Stack Trace: ' + ex.getStackTraceString();
            result.requestBody = result.requestBody != null ? result.requestBody : 'Payload not generated due to error';
        }

        return result;
    }

    /**
    * @description Retrieves API configuration from metadata
    */
    public static PAID_API_Configuration__mdt getAPIConfiguration(String operationType) {
        String searchOperation = operationType + ' Payment';

        List<PAID_API_Configuration__mdt> configs = [
            SELECT Endpoint_Path__c, HTTP_Method__c, Named_Credential__c, Content_Type__c
            FROM PAID_API_Configuration__mdt
            WHERE Operation_Type__c = :searchOperation
            AND Active__c = true
            LIMIT 1
        ];

        return configs.isEmpty() ? null : configs[0];
    }

    /**
    * @description Makes HTTP callout to PAID API
    */
    public static HttpResponse makeCallout(
        PAID_API_Configuration__mdt config,
        String requestBody,
        String paymentExternalId
    ) {
        HttpRequest request = new HttpRequest();

        String endpoint = 'callout:' + config.Named_Credential__c;
        String apiPath = config.Endpoint_Path__c;

        if (String.isNotBlank(paymentExternalId)) {
            apiPath = apiPath.replace(':paymentId', paymentExternalId);
            apiPath = apiPath.replace('{paymentId}', paymentExternalId);
        }

        endpoint += apiPath;

        request.setEndpoint(endpoint);
        request.setMethod(config.HTTP_Method__c);

        String contentType = String.isNotBlank(config.Content_Type__c)
            ? config.Content_Type__c
            : 'application/json';

        request.setHeader('Content-Type', contentType);
        request.setBody(requestBody);

        Http http = new Http();
        return http.send(request);
    }

    /**
    * @description Extracts Payment ID from PAID response
    */
    public static String extractPaymentId(Map<String, Object> responseMap) {
        if (responseMap.containsKey('id')) {
            return String.valueOf(responseMap.get('id'));
        }

        if (responseMap.containsKey('paymentId')) {
            return String.valueOf(responseMap.get('paymentId'));
        }

        if (responseMap.containsKey('data')) {
            Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
            if (dataMap != null && dataMap.containsKey('id')) {
                return String.valueOf(dataMap.get('id'));
            }
        }

        throw new PAIDPaymentException('Unable to extract Payment ID from response');
    }

    /**
    * @description Wrapper class to hold callout results
    */
    public class CalloutResult {
        public Id paymentId;
        public Boolean success;
        public String requestBody;
        public String responseBody;
        public Integer statusCode;
        public String errorMessage;
        public String paidExternalId;

        public CalloutResult() {
            this.success = false;
        }
    }

    /**
    * @description Custom exception
    */
    public class PAIDPaymentException extends Exception {}
}