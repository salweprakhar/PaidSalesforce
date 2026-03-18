public class OrderRequestWrapper {

    public String status;
    public Data data;
    public String message;

    public class Data {
        public String id;
        public String customerId;
        public String billingCustomerId;
        public String organizationId;
        public String name;
        public String startDate;
        public String currencyType;

        public Customer customer;
        public List<OrderLine> OrderLine;
    }

    public class Customer {
        public String id;
        public String name;
        public String externalId;
        public String defaultCurrency;
        public BillingAddress billingAddress;
    }

    public class BillingAddress {
        public String city;
        public String line1;
        public String state;
        public String country;
        public String zipCode;
    }

    public class OrderLine {
        public String id;
        public String orderId;
        public String productId;
        public String name;
        public String startDate;
        public String endDate;
        public String creationState;
        public String lineType;

        public Product product;
        public List<OrderLineAttribute> OrderLineAttribute;
    }

    public class Product {
        public String id;
        public String name;
        public String type;
        public Boolean active;
        public String externalId;
        public String displayId;
    }

    public class OrderLineAttribute {
        public String id;
        public String orderLineId;
        public String productAttributeId;
        public String currencyType;
        public Decimal quantity;
		public String creationState;
		public String discountType;
        public Decimal discountPercent;
        public Decimal discountAmount;
		public Decimal unitPrice;
		public Decimal billingPeriods;
		public Decimal discountedUnitPrice;
		public Decimal periodAmountExclTax;
		public Decimal contractAmountExclTax;
		public Decimal contractEstimatedTax;
		public Decimal contractAmountInclTax;
		public Decimal billedAmountExclTax;
		public Decimal billedTax;
		public Decimal totalBilling;

        public Pricing pricing;
        public ProductAttribute productAttribute;
    }

    public class Pricing {
        public Boolean taxable;
        public String chargeType;
        public String pricingModel;
        public String billingType;
        public String billingFrequency;
        public String eventName;
        public Decimal billingFrequencyCustomMonths;
        public PricePoint pricePoint;
    }

    public class PricePoint {
        public String currencyType;
        public Decimal unitPrice;
        public Decimal minQuantity;
        public Decimal includedQuantity;
        public List<Tier> tiers;
    }

    public class Tier {
        public Decimal lowerBound;
        public Decimal upperBound;
        public Decimal unitAmount;
    }

    public class ProductAttribute {
        public String id;
        public String name;
        public String type;
        public Boolean active;
    }
}