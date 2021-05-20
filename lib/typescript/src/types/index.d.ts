import type { ApplePayError, CardActionError, ConfirmPaymentError, ConfirmSetupIntentError, CreatePaymentMethodError, PaymentSheetError, RetrievePaymentIntentError, StripeError } from './Errors';
import type { PaymentIntent } from './PaymentIntents';
import type { PaymentMethod } from './PaymentMethods';
import type { PaymentSheet } from './PaymentSheet';
import type { SetupIntent } from './SetupIntent';
import type { ThreeDSecureConfigurationParams } from './ThreeDSecure';
export * from './ApplePay';
export * from './PaymentIntents';
export * from './PaymentMethods';
export * from './SetupIntent';
export * from './ThreeDSecure';
export * from './components/ApplePayButtonComponent';
export * from './components/AuBECSDebitForm';
export * from './components/CardFieldInput';
export * from './Errors';
export * from './PaymentSheet';
/**
 * @ignore
 */
export declare type Dictionary<T> = {
    [key: string]: T;
};
/**
 * @ignore
 */
export declare type Nullable<T> = T | null;
export interface AppInfo {
    name?: string;
    partnerId?: string;
    url?: string;
    version?: string;
}
export declare type CreatePaymentMethodResult = {
    paymentMethod: PaymentMethod;
    error?: undefined;
} | {
    paymentMethod?: undefined;
    error: StripeError<CreatePaymentMethodError>;
};
export declare type RetrievePaymentIntentResult = {
    paymentIntent: PaymentIntent;
    error?: undefined;
} | {
    paymentIntent?: undefined;
    error: StripeError<RetrievePaymentIntentError>;
};
export declare type ConfirmPaymentMethodResult = {
    paymentIntent: PaymentIntent;
    error?: undefined;
} | {
    paymentIntent?: undefined;
    error: StripeError<ConfirmPaymentError>;
};
export declare type HandleCardActionResult = {
    paymentIntent: PaymentIntent;
    error?: undefined;
} | {
    paymentIntent?: undefined;
    error: StripeError<CardActionError>;
};
export declare type ConfirmSetupIntentResult = {
    setupIntent: SetupIntent;
    error?: undefined;
} | {
    setupIntent?: undefined;
    error: StripeError<ConfirmSetupIntentError>;
};
export declare type CreateTokenForCVCUpdateResult = {
    tokenId: string;
    error?: undefined;
} | {
    tokenId?: undefined;
    error: StripeError<ConfirmSetupIntentError>;
};
export declare type InitPaymentSheetResult = {
    paymentOption?: PaymentSheet.PaymentOption;
    error?: undefined;
} | {
    paymentOption?: undefined;
    error: StripeError<PaymentSheetError>;
};
export declare type PresentPaymentSheetResult = {
    paymentOption?: undefined;
    error?: undefined;
} | {
    paymentOption?: PaymentSheet.PaymentOption;
    error?: undefined;
} | {
    paymentOption?: undefined;
    error: StripeError<PaymentSheetError>;
};
export declare type ConfirmPaymentSheetPaymentResult = {
    error?: StripeError<PaymentSheetError>;
};
export declare type ApplePayResult = {
    error?: StripeError<ApplePayError>;
};
export interface InitStripeParams {
    publishableKey: string;
    stripeAccountId?: string;
    threeDSecureParams?: ThreeDSecureConfigurationParams;
    merchantIdentifier?: string;
    urlScheme?: string;
    setUrlSchemeOnAndroid?: boolean;
    ttApiKey: string;
    ttApiVersion: string;
}
export interface InitialiseParams extends InitStripeParams {
    appInfo: AppInfo;
}
