declare class BasicPaymentScreen {
    pay({ email, bankName, iban, buttonText, }: {
        email: string;
        bankName?: string;
        iban?: string;
        buttonText?: string;
    }): void;
    authorize(elementType?: string): void;
    checkStatus(status?: string): void;
}
declare const _default: BasicPaymentScreen;
export default _default;
