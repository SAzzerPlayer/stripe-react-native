export declare namespace PaymentSheet {
    type SetupParams = GooglePayParams & ApplePayParams & {
        customerId?: string;
        customerEphemeralKeySecret?: string;
        paymentIntentClientSecret: string;
        customFlow?: boolean;
        merchantDisplayName?: string;
        style?: 'alwaysLight' | 'alwaysDark' | 'automatic';
    };
    type PresentParams = {
        confirmPayment?: false;
    } | {
        clientSecret: string;
        confirmPayment?: true;
    };
    type ApplePayParams = {
        applePay?: true;
        merchantCountryCode: string;
    } | {
        applePay?: false;
        merchantCountryCode?: string;
    };
    type GooglePayParams = {
        googlePay?: true;
        merchantCountryCode: string;
        testEnv?: boolean;
    } | {
        googlePay?: false;
        merchantCountryCode?: string;
        testEnv?: boolean;
    };
    interface PaymentOption {
        label: string;
        image: string;
    }
}
