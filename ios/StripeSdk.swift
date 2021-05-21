import PassKit
import Stripe

@objc(StripeSdk)
class StripeSdk: RCTEventEmitter, STPApplePayContextDelegate, STPBankSelectionViewControllerDelegate, UIAdaptivePresentationControllerDelegate, STPPaymentContextDelegate, PKPaymentAuthorizationViewControllerDelegate {

    var merchantIdentifier: String? = nil

    private var paymentSheet: PaymentSheet?
    private var paymentSheetFlowController: PaymentSheet.FlowController?

    var urlScheme: String? = nil

    var applePayCompletionCallback: STPIntentClientSecretCompletionBlock? = nil
    var applePayRequestResolver: RCTPromiseResolveBlock? = nil
    var applePayRequestRejecter: RCTPromiseRejectBlock? = nil
    var applePayCompletionRejecter: RCTPromiseRejectBlock? = nil
    var confirmApplePayPaymentResolver: RCTPromiseResolveBlock? = nil
    var confirmPaymentResolver: RCTPromiseResolveBlock? = nil
    var confirmPaymentRejecter: RCTPromiseRejectBlock? = nil

    var customerContext: STPCustomerContext? = nil
    var paymentContext: STPPaymentContext? = nil

    var requestIsCompleted: Bool = true

    var isApplePayUsed: Bool = false
    var lastPaymentMethodId: String? = nil

    var paymentMethodIdResolver: RCTPromiseResolveBlock? = nil
    var applePayResolver: RCTPromiseResolveBlock? = nil
    var applePayRejecter: RCTPromiseRejectBlock? = nil

    var confirmPaymentClientSecret: String? = nil

    var appleAuthCompletion: ((PKPaymentAuthorizationResult) -> Void)?

    var shippingMethodUpdateHandler: ((PKPaymentRequestShippingMethodUpdate) -> Void)? = nil
    var shippingContactUpdateHandler: ((PKPaymentRequestShippingContactUpdate) -> Void)? = nil

    override func supportedEvents() -> [String]! {
        return ["onDidSetShippingMethod", "onDidSetShippingContact", "onDidSelectPaymentMethod"]
    }

    @objc override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc(initialise:resolver:rejecter:)
    func initialise(params: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        let publishableKey = params["publishableKey"] as! String
        let appInfo = params["appInfo"] as! NSDictionary
        let stripeAccountId = params["stripeAccountId"] as? String
        let params3ds = params["threeDSecureParams"] as? NSDictionary
        let urlScheme = params["urlScheme"] as? String
        let merchantIdentifier = params["merchantIdentifier"] as? String
        let ttApiKey = params["ttApiKey"] as? String
        let ttApiVersion = params["ttApiVersion"] as? String

        if let params3ds = params3ds {
            configure3dSecure(params3ds)
        }

        self.urlScheme = urlScheme

        STPAPIClient.shared.publishableKey = publishableKey
        STPAPIClient.shared.stripeAccount = stripeAccountId

        let name = RCTConvert.nsString(appInfo["name"]) ?? ""
        let partnerId = RCTConvert.nsString(appInfo["partnerId"]) ?? ""
        let version = RCTConvert.nsString(appInfo["version"]) ?? ""
        let url = RCTConvert.nsString(appInfo["url"]) ?? ""

        TTApiClient.sharedClient.baseURLString = "https://api.tokentransit.com/user/"
        TTApiClient.sharedClient.ttApiKey = ttApiKey
        TTApiClient.sharedClient.ttApiVersion = ttApiVersion

        STPAPIClient.shared.appInfo = STPAppInfo(name: name, partnerId: partnerId, version: version, url: url)
        self.merchantIdentifier = merchantIdentifier
        resolve(NSNull())
    }

    @objc(setSessionId:)
    func setSessionId(sessionId: String) -> Void {
        TTApiClient.sharedClient.sessionId = sessionId;
    }

    @objc(initCustomerContext:rejecter:)
    func initCustomerContext(resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        TTApiClient.sharedClient.resolve = resolve
        TTApiClient.sharedClient.reject = reject
        customerContext = STPCustomerContext(keyProvider: TTApiClient.sharedClient)
    }

    @objc(showPaymentOptionsModal)
    func showPaymentOptionsModal() -> Void {
        DispatchQueue.main.async {
            let viewController = UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()

            let paymentConfig = STPPaymentConfiguration()
            paymentConfig.applePayEnabled = true
            paymentConfig.appleMerchantIdentifier = self.merchantIdentifier

            self.paymentContext = STPPaymentContext.init(customerContext: self.customerContext!, configuration: paymentConfig, theme: STPTheme.defaultTheme)

            self.paymentContext?.delegate = self as STPPaymentContextDelegate
            self.paymentContext?.hostViewController = viewController

            self.paymentContext?.presentPaymentOptionsViewController()
        }
    }


    @objc(getPaymentMethodId:resolver:rejecter:)
    func getPaymentMethodId(summaryItems: NSArray, resolver resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        paymentMethodIdResolver = resolve
        if(self.isApplePayUsed) {
            self.paymentRequestWithApplePay(summaryItems, withOptions: [:], resolver: resolve, rejecter: reject)
        }
        else {
            if (self.paymentContext !== nil && paymentContext?.selectedPaymentOption !== nil) {
                resolve(lastPaymentMethodId)
            } else {
                resolve(nil)
            }
        }

    }

    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        let rootVC = UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()
        rootVC.dismiss(animated: true, completion: nil)
        requestIsCompleted = true
    }

    func resolveApplePayCompletion(status: PKPaymentAuthorizationStatus) {
        let result = PKPaymentAuthorizationResult.init()
        result.status = status
        if (appleAuthCompletion != nil) {
            appleAuthCompletion!(result)
        }
    }

    func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {

        appleAuthCompletion = completion
        STPAPIClient.shared.createPaymentMethod(with: payment) { (token, error) in

            if(error != nil) {
                self.applePayRejecter!("4", error.debugDescription, nil)
                self.resolveApplePayCompletion(status: PKPaymentAuthorizationStatus.failure)
            } else {
                self.applePayResolver!(token?.stripeId)
                self.resolveApplePayCompletion(status: PKPaymentAuthorizationStatus.success)
            }

        }
    }

    func paymentAuthorizationViewControllerWillAuthorizePayment(_ controller: PKPaymentAuthorizationViewController) {

    }

    @objc(paymentRequestWithApplePay:withOptions:resolver:rejecter:)
    func paymentRequestWithApplePay(_ summaryItems: NSArray, withOptions options: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) -> Void {
        applePayResolver = resolve
        applePayRejecter = reject
        if(!requestIsCompleted) {
            reject("2", "ApplePay is busy", nil)
            return
        }

        requestIsCompleted = false

        var cartSummaryItems: [PKPaymentSummaryItem] = []

        if let items = summaryItems as? [[String : Any]] {
            for item in items {
                let label = item["label"] as? String ?? ""
                let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
                let type = Mappers.mapToPaymentSummaryItemType(type: item["type"] as? String)
                cartSummaryItems.append(PKPaymentSummaryItem(label: label, amount: amount, type: type))
            }
        }


        let paymentRequest = StripeAPI.paymentRequest(withMerchantIdentifier: merchantIdentifier!, country: "US", currency: "USD")

        let requiredShippingAddressFields = NSArray()
        let requiredBillingContactFields = NSArray()
        let shippingMethods = NSArray()

        paymentRequest.requiredShippingContactFields = Set(requiredShippingAddressFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.requiredBillingContactFields = Set(requiredBillingContactFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.shippingMethods = Mappers.mapToShippingMethods(shippingMethods: shippingMethods)

        paymentRequest.paymentSummaryItems = cartSummaryItems

        DispatchQueue.main.async {
            let rootVC = UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()
            let paymentAuthorizationVC = PKPaymentAuthorizationViewController.init(paymentRequest: paymentRequest)


            paymentAuthorizationVC?.delegate = self

            rootVC.present(paymentAuthorizationVC!, animated: true, completion: nil)
        }

    }

    func paymentContext(_ paymentContext: STPPaymentContext, didFailToLoadWithError error: Error) {

    }

    func paymentContextDidChange(_ paymentContext: STPPaymentContext) {
        if let pContext = paymentContext.selectedPaymentOption as? STPPaymentMethod {
            isApplePayUsed = false
            let label = pContext.label
            let image = self.encodeToBase64String(image: pContext.image)
            let id = pContext.stripeId
            lastPaymentMethodId = id
            self.sendEvent(withName: "onDidSelectPaymentMethod", body: [
                "label": label,
                "image": image,
                "methodId": id,
                "useGooglePay": false,
                "useApplePay": isApplePayUsed,
            ])
        } else {
            isApplePayUsed = true
            self.sendEvent(withName: "onDidSelectPaymentMethod", body: [
                "label": nil,
                "image": nil,
                "methodId": nil,
                "useGooglePay": false,
                "useApplePay": isApplePayUsed,
            ])
        }
    }

    func encodeToBase64String(image: UIImage) -> String {
        let imageData:NSData = image.pngData()! as NSData
        return imageData.base64EncodedString(options: NSData.Base64EncodingOptions.lineLength64Characters)
    }

    func paymentContext(_ paymentContext: STPPaymentContext, didCreatePaymentResult paymentResult: STPPaymentResult, completion: @escaping STPPaymentStatusBlock) {
        paymentMethodIdResolver!(paymentResult.paymentMethod!.stripeId);
    }

    func paymentContext(_ paymentContext: STPPaymentContext, didFinishWith status: STPPaymentStatus, error: Error?) {

    }

    @objc(initPaymentSheet:resolver:rejecter:)
    func initPaymentSheet(params: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) -> Void  {
        guard let paymentIntentClientSecret = params["paymentIntentClientSecret"] as? String else {
            reject(PaymentSheetErrorType.Failed.rawValue, "You must provide the paymentIntentClientSecret", nil)
            return
        }


        var configuration = PaymentSheet.Configuration()

        if  params["applePay"] as? Bool == true {
            if let merchantIdentifier = self.merchantIdentifier, let merchantCountryCode = params["merchantCountryCode"] as? String {
                configuration.applePay = .init(merchantId: merchantIdentifier,
                                               merchantCountryCode: merchantCountryCode)
            } else {
                reject(PaymentSheetErrorType.Failed.rawValue, "merchantIdentifier or merchantCountryCode is not provided", nil)
            }
        }

        if let merchantDisplayName = params["merchantDisplayName"] as? String {
            configuration.merchantDisplayName = merchantDisplayName
        }

        if let customerId = params["customerId"] as? String {
            if let customerEphemeralKeySecret = params["customerEphemeralKeySecret"] as? String {
                configuration.customer = .init(id: customerId, ephemeralKeySecret: customerEphemeralKeySecret)
            }
        }

        if #available(iOS 13.0, *) {
            if let style = params["style"] as? String {
                configuration.style = Mappers.mapToUserInterfaceStyle(style)
            }
        }

        if params["customFlow"] as? Bool == true {
            PaymentSheet.FlowController.create(paymentIntentClientSecret: paymentIntentClientSecret,
                                               configuration: configuration) { [weak self] result in
                switch result {
                case .failure(let error):
                    reject("Failed", error.localizedDescription, nil)
                case .success(let paymentSheetFlowController):
                    self?.paymentSheetFlowController = paymentSheetFlowController
                    if let paymentOption = self?.paymentSheetFlowController?.paymentOption {
                        let option: NSDictionary = [
                            "label": paymentOption.label,
                            "image": paymentOption.image.pngData()?.base64EncodedString() ?? ""
                        ]
                        resolve(option)
                    } else {
                        reject("Failed", "in else", nil)
                    }
                }
            }
        } else {
            self.paymentSheet = PaymentSheet(paymentIntentClientSecret: paymentIntentClientSecret, configuration: configuration)
            resolve(NSNull())
        }
    }

    @objc(confirmPaymentSheetPayment:rejecter:)
    func confirmPaymentSheetPayment(resolver resolve: @escaping RCTPromiseResolveBlock,
                                    rejecter reject: @escaping RCTPromiseRejectBlock) -> Void  {
        DispatchQueue.main.async {
            self.paymentSheetFlowController?.confirm(from: UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()) { paymentResult in
                switch paymentResult {
                case .completed:
                    resolve([])
                case .canceled:
                    reject(PaymentSheetErrorType.Canceled.rawValue, "The payment has been canceled", nil)
                case .failed(let error):
                    reject(PaymentSheetErrorType.Failed.rawValue, error.localizedDescription, nil)
                }
            }
        }
    }

    @objc(presentPaymentSheet:resolver:rejecter:)
    func presentPaymentSheet(params: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) -> Void  {
        let confirmPayment = params["confirmPayment"] as? Bool

        DispatchQueue.main.async {
            if (confirmPayment == false) {
                self.paymentSheetFlowController?.presentPaymentOptions(from: UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()) {
                    if let paymentOption = self.paymentSheetFlowController?.paymentOption {
                        let option: NSDictionary = [
                            "label": paymentOption.label,
                            "image": paymentOption.image.pngData()?.base64EncodedString() ?? ""
                        ]
                        resolve(["paymentOption": option])
                    } else {
                        resolve(NSNull())
                    }
                }
            } else {
                self.paymentSheet?.present(from: UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController()) { paymentResult in
                    switch paymentResult {
                    case .completed:
                        resolve([])
                    case .canceled:
                        reject(PaymentSheetErrorType.Canceled.rawValue, "The payment has been canceled", nil)
                    case .failed(let error):
                        reject(PaymentSheetErrorType.Failed.rawValue, error.localizedDescription, nil)
                    }
                }
            }
        }
    }



    @objc(createTokenForCVCUpdate:resolver:rejecter:)
    func createTokenForCVCUpdate(cvc: String?, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let cvc = cvc else {
            reject("Failed", "You must provide CVC", nil)
            return;
        }

        STPAPIClient.shared.createToken(forCVCUpdate: cvc) { (token, error) in
            if error != nil || token == nil {
                reject("Failed", error?.localizedDescription, nil)
            } else {
                let tokenId = token?.tokenId
                resolve(tokenId)
            }
        }
    }

    @objc(confirmSetupIntent:data:options:resolver:rejecter:)
    func confirmSetupIntent (setupIntentClientSecret: String, params: NSDictionary,
                             options: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
        let type = Mappers.mapToPaymentMethodType(type: params["type"] as? String)
        guard let paymentMethodType = type else {
            reject(ConfirmPaymentErrorType.Failed.rawValue, "You must provide paymentMethodType", nil)
            return
        }

        let cardFieldUIManager = bridge.module(forName: "CardFieldManager") as? CardFieldManager
        let cardFieldView = cardFieldUIManager?.getCardFieldReference(id: CARD_FIELD_INSTANCE_ID) as? CardFieldView

        var paymentMethodParams: STPPaymentMethodParams?
        let factory = PaymentMethodFactory.init(params: params, cardFieldView: cardFieldView)

        do {
            paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
        } catch  {
            reject(ConfirmPaymentErrorType.Failed.rawValue, error.localizedDescription, nil)
        }
        guard paymentMethodParams != nil else {
            reject(ConfirmPaymentErrorType.Unknown.rawValue, "Unhandled error occured", nil)
            return
        }

        let setupIntentParams = STPSetupIntentConfirmParams(clientSecret: setupIntentClientSecret)
        setupIntentParams.paymentMethodParams = paymentMethodParams

        if let urlScheme = urlScheme {
            setupIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
        }

        let paymentHandler = STPPaymentHandler.shared()
        paymentHandler.confirmSetupIntent(setupIntentParams, with: self) { status, setupIntent, error in
            switch (status) {
            case .failed:
                reject(ConfirmSetupIntentErrorType.Failed.rawValue, error?.localizedDescription ?? "", nil)
                break
            case .canceled:
                reject(ConfirmSetupIntentErrorType.Canceled.rawValue, error?.localizedDescription ?? "", nil)
                break
            case .succeeded:
                let intent = Mappers.mapFromSetupIntent(setupIntent: setupIntent!)
                resolve(intent)
            @unknown default:
                reject(ConfirmSetupIntentErrorType.Unknown.rawValue, error?.localizedDescription ?? "", nil)
                break
            }
        }
    }

    @objc(updateApplePaySummaryItems:resolver:rejecter:)
    func updateApplePaySummaryItems(summaryItems: NSArray, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        if (shippingMethodUpdateHandler == nil && shippingContactUpdateHandler == nil) {
            reject(ApplePayErrorType.Failed.rawValue, "You can use this method only after either onDidSetShippingMethod or onDidSetShippingContact events emitted", nil)
            return
        }
        var paymentSummaryItems: [PKPaymentSummaryItem] = []
        if let items = summaryItems as? [[String : Any]] {
            for item in items {
                let label = item["label"] as? String ?? ""
                let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
                let type = Mappers.mapToPaymentSummaryItemType(type: item["type"] as? String)
                paymentSummaryItems.append(PKPaymentSummaryItem(label: label, amount: amount, type: type))
            }
        }
        shippingMethodUpdateHandler?(PKPaymentRequestShippingMethodUpdate.init(paymentSummaryItems: paymentSummaryItems))
        shippingContactUpdateHandler?(PKPaymentRequestShippingContactUpdate.init(paymentSummaryItems: paymentSummaryItems))
        self.shippingMethodUpdateHandler = nil
        self.shippingContactUpdateHandler = nil
        resolve(NSNull())
    }


    func applePayContext(_ context: STPApplePayContext, didSelect shippingMethod: PKShippingMethod, handler: @escaping (PKPaymentRequestShippingMethodUpdate) -> Void) {
        self.shippingMethodUpdateHandler = handler
        sendEvent(withName: "onDidSetShippingMethod", body: ["shippingMethod": Mappers.mapFromShippingMethod(shippingMethod: shippingMethod)])
    }

    func applePayContext(_ context: STPApplePayContext, didSelectShippingContact contact: PKContact, handler: @escaping (PKPaymentRequestShippingContactUpdate) -> Void) {
        self.shippingContactUpdateHandler = handler
        sendEvent(withName: "onDidSetShippingContact", body: ["shippingContact": Mappers.mapFromShippingContact(shippingContact: contact)])
    }

    func applePayContext(_ context: STPApplePayContext, didCreatePaymentMethod paymentMethod: STPPaymentMethod, paymentInformation: PKPayment, completion: @escaping STPIntentClientSecretCompletionBlock) {
        self.applePayCompletionCallback = completion
        self.applePayRequestResolver?([NSNull()])
    }

    @objc(confirmApplePayPayment:resolver:rejecter:)
    func confirmApplePayPayment(clientSecret: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        self.applePayCompletionRejecter = reject
        self.applePayCompletionCallback?(clientSecret, nil)
        self.confirmApplePayPaymentResolver = resolve
    }

    func applePayContext(_ context: STPApplePayContext, didCompleteWith status: STPPaymentStatus, error: Error?) {
        switch status {
        case .success:
            applePayCompletionRejecter = nil
            applePayRequestRejecter = nil
            confirmApplePayPaymentResolver?([NSNull()])
            break
        case .error:
            let message = "Apple pay completion failed"
            applePayCompletionRejecter?(ApplePayErrorType.Failed.rawValue, message, nil)
            applePayRequestRejecter?(ApplePayErrorType.Failed.rawValue, message, nil)
            applePayCompletionRejecter = nil
            applePayRequestRejecter = nil
            break
        case .userCancellation:
            let message = "Apple pay payment has been cancelled"
            applePayCompletionRejecter?(ApplePayErrorType.Canceled.rawValue, message, nil)
            applePayRequestRejecter?(ApplePayErrorType.Canceled.rawValue, message, nil)
            applePayCompletionRejecter = nil
            applePayRequestRejecter = nil
            break
        @unknown default:
            let message = "Cannot complete payment"
            applePayCompletionRejecter?(ApplePayErrorType.Unknown.rawValue, message, nil)
            applePayRequestRejecter?(ApplePayErrorType.Unknown.rawValue, message, nil)
            applePayCompletionRejecter = nil
            applePayRequestRejecter = nil
        }
    }

    @objc(isApplePaySupported:rejecter:)
    func isApplePaySupported(resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
        let isSupported = StripeAPI.deviceSupportsApplePay()
        resolve(isSupported)
    }

    @objc(handleURLCallback:resolver:rejecter:)
    func handleURLCallback(url: String?, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
      guard let url = url else {
        resolve(false)
        return;
      }
      let urlObj = URL(string: url)
      if (urlObj == nil) {
        resolve(false)
      } else {
        DispatchQueue.main.async {
          let stripeHandled = StripeAPI.handleURLCallback(with: urlObj!)
          resolve(stripeHandled)
        }
      }
    }

    @objc(presentApplePay:resolver:rejecter:)
    func presentApplePay(params: NSDictionary,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
        if (merchantIdentifier == nil) {
            reject(ApplePayErrorType.Failed.rawValue, "You must provide merchantIdentifier", nil)
            return
        }

        guard let summaryItems = params["cartItems"] as? NSArray else {
            reject(ApplePayErrorType.Failed.rawValue, "You must provide the items for purchase", nil)
            return
        }
        guard let country = params["country"] as? String else {
            reject(ApplePayErrorType.Failed.rawValue, "You must provide the country", nil)
            return
        }
        guard let currency = params["currency"] as? String else {
            reject(ApplePayErrorType.Failed.rawValue, "You must provide the payment currency", nil)
            return
        }

        self.applePayRequestResolver = resolve
        self.applePayRequestRejecter = reject

        let merchantIdentifier = self.merchantIdentifier ?? ""
        let paymentRequest = StripeAPI.paymentRequest(withMerchantIdentifier: merchantIdentifier, country: country, currency: currency)

        let requiredShippingAddressFields = params["requiredShippingAddressFields"] as? NSArray ?? NSArray()
        let requiredBillingContactFields = params["requiredBillingContactFields"] as? NSArray ?? NSArray()
        let shippingMethods = params["shippingMethods"] as? NSArray ?? NSArray()

        paymentRequest.requiredShippingContactFields = Set(requiredShippingAddressFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.requiredBillingContactFields = Set(requiredBillingContactFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.shippingMethods = Mappers.mapToShippingMethods(shippingMethods: shippingMethods)

        var paymentSummaryItems: [PKPaymentSummaryItem] = []

        if let items = summaryItems as? [[String : Any]] {
            for item in items {
                let label = item["label"] as? String ?? ""
                let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
                let type = Mappers.mapToPaymentSummaryItemType(type: item["type"] as? String)
                paymentSummaryItems.append(PKPaymentSummaryItem(label: label, amount: amount, type: type))
            }
        }

        paymentRequest.paymentSummaryItems = paymentSummaryItems
        if let applePayContext = STPApplePayContext(paymentRequest: paymentRequest, delegate: self) {
            DispatchQueue.main.async {
                applePayContext.presentApplePay(on: UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController())
            }
        } else {
            reject(ApplePayErrorType.Failed.rawValue, "Apple pay request failed", nil)
        }
    }

    func configure3dSecure(_ params: NSDictionary) {
        let threeDSCustomizationSettings = STPPaymentHandler.shared().threeDSCustomizationSettings
        let uiCustomization = Mappers.mapUICustomization(params)

        threeDSCustomizationSettings.uiCustomization = uiCustomization
    }

    @objc(createPaymentMethod:options:resolver:rejecter:)
    func createPaymentMethod(
        params: NSDictionary,
        options: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        let type = Mappers.mapToPaymentMethodType(type: params["type"] as? String)
        guard let paymentMethodType = type else {
            reject(NextPaymentActionErrorType.Failed.rawValue, "You must provide paymentMethodType", nil)
            return
        }

        let cardFieldUIManager = bridge.module(forName: "CardFieldManager") as? CardFieldManager
        let cardFieldView = cardFieldUIManager?.getCardFieldReference(id: CARD_FIELD_INSTANCE_ID) as? CardFieldView

        var paymentMethodParams: STPPaymentMethodParams?
        let factory = PaymentMethodFactory.init(params: params, cardFieldView: cardFieldView)

        do {
            paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
        } catch  {
            reject(NextPaymentActionErrorType.Failed.rawValue, error.localizedDescription, nil)
        }

        guard let params = paymentMethodParams else {
            reject(NextPaymentActionErrorType.Unknown.rawValue, "Unhandled error occured", nil)
            return
        }

        STPAPIClient.shared.createPaymentMethod(with: params) { paymentMethod, error in
            if let createError = error {
                reject(NextPaymentActionErrorType.Failed.rawValue, createError.localizedDescription, nil)
            }

            if let paymentMethod = paymentMethod {
                let method = Mappers.mapFromPaymentMethod(paymentMethod)
                resolve(method)
            }
        }
    }

    @objc(handleCardAction:resolver:rejecter:)
    func handleCardAction(
        paymentIntentClientSecret: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ){
        let paymentHandler = STPPaymentHandler.shared()
        paymentHandler.handleNextAction(forPayment: paymentIntentClientSecret, with: self, returnURL: nil) { status, paymentIntent, handleActionError in
            switch (status) {
            case .failed:
                reject(NextPaymentActionErrorType.Failed.rawValue, handleActionError?.localizedDescription ?? "", nil)
                break
            case .canceled:
                reject(NextPaymentActionErrorType.Canceled.rawValue, handleActionError?.localizedDescription ?? "", nil)
                break
            case .succeeded:
                if let paymentIntent = paymentIntent {
                    resolve(Mappers.mapFromPaymentIntent(paymentIntent: paymentIntent))
                }
                break
            @unknown default:
                reject(NextPaymentActionErrorType.Unknown.rawValue, "Cannot complete payment", nil)
                break
            }
        }
    }

    @objc(confirmPaymentMethod:data:options:resolver:rejecter:)
    func confirmPaymentMethod(
        paymentIntentClientSecret: String,
        params: NSDictionary,
        options: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        self.confirmPaymentResolver = resolve
        self.confirmPaymentRejecter = reject
        self.confirmPaymentClientSecret = paymentIntentClientSecret

        let cardFieldUIManager = bridge.module(forName: "CardFieldManager") as? CardFieldManager
        let cardFieldView = cardFieldUIManager?.getCardFieldReference(id: CARD_FIELD_INSTANCE_ID) as? CardFieldView

        let paymentMethodId = params["paymentMethodId"] as? String
        let paymentIntentParams = STPPaymentIntentParams(clientSecret: paymentIntentClientSecret)
        if let setupFutureUsage = params["setupFutureUsage"] as? String {
            paymentIntentParams.setupFutureUsage = Mappers.mapToPaymentIntentFutureUsage(usage: setupFutureUsage)
        }

        let type = Mappers.mapToPaymentMethodType(type: params["type"] as? String)
        guard let paymentMethodType = type else {
            reject(ConfirmPaymentErrorType.Failed.rawValue, "You must provide paymentMethodType", nil)
            return
        }

        if (paymentMethodType == STPPaymentMethodType.FPX) {
            let testOfflineBank = params["testOfflineBank"] as? Bool
            if (testOfflineBank == false || testOfflineBank == nil) {
                payWithFPX(paymentIntentClientSecret)
                return
            }
        }
        if paymentMethodId != nil {
            paymentIntentParams.paymentMethodId = paymentMethodId
        } else {
            var paymentMethodParams: STPPaymentMethodParams?
            var paymentMethodOptions: STPConfirmPaymentMethodOptions?
            let factory = PaymentMethodFactory.init(params: params, cardFieldView: cardFieldView)

            do {
                paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
                paymentMethodOptions = try factory.createOptions(paymentMethodType: paymentMethodType)
            } catch  {
                reject(ConfirmPaymentErrorType.Failed.rawValue, error.localizedDescription, nil)
            }
            guard paymentMethodParams != nil else {
                reject(ConfirmPaymentErrorType.Unknown.rawValue, "Unhandled error occured", nil)
                return
            }
            paymentIntentParams.paymentMethodParams = paymentMethodParams
            paymentIntentParams.paymentMethodOptions = paymentMethodOptions
            paymentIntentParams.shipping = Mappers.mapToShippingDetails(shippingDetails: params["shippingDetails"] as? NSDictionary)

            if let urlScheme = urlScheme {
                paymentIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
            }
        }

        let paymentHandler = STPPaymentHandler.shared()
        paymentHandler.confirmPayment(paymentIntentParams, with: self, completion: onCompleteConfirmPayment)
    }

    @objc(retrievePaymentIntent:resolver:rejecter:)
    func retrievePaymentIntent(
        clientSecret: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        STPAPIClient.shared.retrievePaymentIntent(withClientSecret: clientSecret) { (paymentIntent, error) in
            guard error == nil else {
                reject(RetrievePaymentIntentErrorType.Unknown.rawValue, error?.localizedDescription, nil)
                return
            }

            if let paymentIntent = paymentIntent {
                resolve(Mappers.mapFromPaymentIntent(paymentIntent: paymentIntent))
            } else {
                reject(RetrievePaymentIntentErrorType.Unknown.rawValue, "Cannot retrieve PaymentIntent", nil)
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        confirmPaymentRejecter?(ConfirmPaymentErrorType.Canceled.rawValue, "FPX Payment has been canceled", nil)
    }

    func payWithFPX(_ paymentIntentClientSecret: String) {
        let vc = STPBankSelectionViewController.init(bankMethod: .FPX)

        vc.delegate = self

        DispatchQueue.main.async {
            vc.presentationController?.delegate = self

            let share = UIApplication.shared.delegate
            share?.window??.rootViewController?.present(vc, animated: true)
        }
    }

    func bankSelectionViewController(_ bankViewController: STPBankSelectionViewController, didCreatePaymentMethodParams paymentMethodParams: STPPaymentMethodParams) {
        guard let clientSecret = confirmPaymentClientSecret else {
            confirmPaymentRejecter?(ConfirmPaymentErrorType.Failed.rawValue, "Missing paymentIntentClientSecret", nil)
            return
        }
        let paymentIntentParams = STPPaymentIntentParams(clientSecret: clientSecret)
        paymentIntentParams.paymentMethodParams = paymentMethodParams

        if let urlScheme = urlScheme {
            paymentIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
        }
        let paymentHandler = STPPaymentHandler.shared()
        bankViewController.dismiss(animated: true)
        paymentHandler.confirmPayment(paymentIntentParams, with: self, completion: onCompleteConfirmPayment)
    }

    func onCompleteConfirmPayment(status: STPPaymentHandlerActionStatus, paymentIntent: STPPaymentIntent?, error: NSError?) {
        self.confirmPaymentClientSecret = nil
        switch (status) {
        case .failed:
            confirmPaymentRejecter?(ConfirmPaymentErrorType.Failed.rawValue, paymentIntent?.lastPaymentError?.message ?? error?.localizedDescription ?? "", nil)
            break
        case .canceled:
            let statusCode: String
            if (paymentIntent?.status == STPPaymentIntentStatus.requiresPaymentMethod) {
                statusCode = ConfirmPaymentErrorType.Failed.rawValue
            } else {
                statusCode = ConfirmPaymentErrorType.Canceled.rawValue
            }
            confirmPaymentRejecter?(statusCode, paymentIntent?.lastPaymentError?.message ?? error?.localizedDescription ?? "", nil)
            break
        case .succeeded:
            if let paymentIntent = paymentIntent {
                let intent = Mappers.mapFromPaymentIntent(paymentIntent: paymentIntent)
                confirmPaymentResolver?(intent)
            }
            break
        @unknown default:
            confirmPaymentRejecter?(ConfirmPaymentErrorType.Unknown.rawValue, "Cannot complete payment", nil)
            break
        }
    }
}

func findViewControllerPresenter(from uiViewController: UIViewController) -> UIViewController {
    // Note: creating a UIViewController inside here results in a nil window
    // This is a bit of a hack: We traverse the view hierarchy looking for the most reasonable VC to present from.
    // A VC hosted within a SwiftUI cell, for example, doesn't have a parent, so we need to find the UIWindow.
    var presentingViewController: UIViewController =
        uiViewController.view.window?.rootViewController ?? uiViewController

    // Find the most-presented UIViewController
    while let presented = presentingViewController.presentedViewController {
        presentingViewController = presented
    }

    return presentingViewController
}

extension StripeSdk: STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        return findViewControllerPresenter(from: UIApplication.shared.delegate?.window??.rootViewController ?? UIViewController())
    }
}
