package com.reactnativestripesdk

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.AsyncTask
import android.os.Bundle
import android.os.Parcelable
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import com.stripe.android.*
import com.stripe.android.googlepaylauncher.GooglePayLauncher
import com.stripe.android.googlepaylauncher.GooglePayPaymentMethodLauncher
import com.stripe.android.model.*
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.view.AddPaymentMethodActivityStarter
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

@ReactModule(name = StripeSdkModule.NAME)
class StripeSdkModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {
  var cardFieldView: StripeSdkCardView? = null
  var cardFormView: CardFormView? = null

  override fun getName(): String {
    return "StripeSdk"
  }
  private lateinit var stripe: Stripe

  private lateinit var publishableKey: String
  private var stripeAccountId: String? = null
  private var paymentSheetFragment: PaymentSheetFragment? = null

  private var urlScheme: String? = null
  private var confirmPromise: Promise? = null
  private var handleCardActionPromise: Promise? = null
  private var confirmSetupIntentPromise: Promise? = null
  private var confirmPaymentSheetPaymentPromise: Promise? = null
  private var presentPaymentSheetPromise: Promise? = null
  private var initPaymentSheetPromise: Promise? = null
  private var ttKeyProvider: TTKeyProvider = TTKeyProvider()
  private lateinit var paymentSession: PaymentSession

  private var isSupportsGooglePay: Boolean = false
  private var lastPaymentMethodId: String? = ""
  private var lastIsGooglePayUsed: Boolean = false
  private var getPaymentMethodIdPromise: Promise? = null
  private var showNativePay: Boolean = false

  private var confirmPaymentClientSecret: String? = null

  private var googlePayFragment: GooglePayFragment? = null
  private var initGooglePayPromise: Promise? = null
  private var presentGooglePayPromise: Promise? = null

  private val mActivityEventListener = object : BaseActivityEventListener() {
    override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
      when (requestCode) {
        LOAD_PAYMENT_DATA_REQUEST_CODE -> {
          when (resultCode) {
            Activity.RESULT_OK -> {
              if (data != null) {
                handleGooglePayResult(data)
              }
            }
            Activity.RESULT_CANCELED -> {
              getPaymentMethodIdPromise?.reject("0", "Request was canceled")
            }
            AutoResolveHelper.RESULT_ERROR -> {
              val status = AutoResolveHelper.getStatusFromIntent(data)
              getPaymentMethodIdPromise?.reject("2", "Cannot get payment method id")
            }
            else -> {
              // Do nothing.
            }
          }
        }
        else -> {
          if (::stripe.isInitialized) {
            paymentSession.handlePaymentData(requestCode, resultCode, data)
            stripe.onSetupResult(requestCode, data, object : ApiResultCallback<SetupIntentResult> {
              override fun onSuccess(result: SetupIntentResult) {
                val setupIntent = result.intent
                when (setupIntent.status) {
                  StripeIntent.Status.Succeeded -> {
                    confirmSetupIntentPromise?.resolve(mapFromSetupIntentResult(setupIntent))
                  }
                  StripeIntent.Status.Canceled -> {
                    val errorMessage = setupIntent.lastSetupError?.message.orEmpty()
                    confirmSetupIntentPromise?.reject(ConfirmSetupIntentErrorType.Canceled.toString(), errorMessage)
                  }
                  else -> {
                    val errorMessage = "unhandled error: ${setupIntent.status}"
                    confirmSetupIntentPromise?.reject(ConfirmSetupIntentErrorType.Unknown.toString(), errorMessage)
                  }
                }
              }

              override fun onError(e: Exception) {
                confirmSetupIntentPromise?.reject(ConfirmSetupIntentErrorType.Failed.toString(), e.message.orEmpty())
              }
            })

            stripe.onPaymentResult(requestCode, data, object : ApiResultCallback<PaymentIntentResult> {
              override fun onSuccess(result: PaymentIntentResult) {
                val paymentIntent = result.intent

                when (paymentIntent.status) {
                  StripeIntent.Status.Succeeded,
                  StripeIntent.Status.Processing,
                  StripeIntent.Status.RequiresCapture -> {
                    confirmPromise?.resolve(mapFromPaymentIntentResult(paymentIntent))
                    handleCardActionPromise?.resolve(mapFromPaymentIntentResult(paymentIntent))
                  }
                  StripeIntent.Status.RequiresAction -> {
                    if (isPaymentIntentNextActionVoucherBased(paymentIntent.nextActionType)) {
                      confirmPromise?.resolve(mapFromPaymentIntentResult(paymentIntent))
                      handleCardActionPromise?.resolve(mapFromPaymentIntentResult(paymentIntent))
                    } else {
                      val errorMessage = paymentIntent.lastPaymentError?.message.orEmpty()
                      confirmPromise?.reject(ConfirmPaymentErrorType.Canceled.toString(), errorMessage)
                      handleCardActionPromise?.reject(NextPaymentActionErrorType.Canceled.toString(), errorMessage)
                    }
                  }
                  StripeIntent.Status.RequiresPaymentMethod -> {
                    val errorMessage = paymentIntent.lastPaymentError?.message.orEmpty()
                    confirmPromise?.reject(ConfirmPaymentErrorType.Failed.toString(), errorMessage)
                    handleCardActionPromise?.reject(NextPaymentActionErrorType.Failed.toString(), errorMessage)
                  }
                  StripeIntent.Status.RequiresConfirmation -> {
                    handleCardActionPromise?.resolve(mapFromPaymentIntentResult(paymentIntent))
                  }
                  StripeIntent.Status.Canceled -> {
                    val errorMessage = paymentIntent.lastPaymentError?.message.orEmpty()
                    confirmPromise?.reject(ConfirmPaymentErrorType.Canceled.toString(), errorMessage)
                    handleCardActionPromise?.reject(NextPaymentActionErrorType.Canceled.toString(), errorMessage)
                  }
                  else -> {
                    val errorMessage = "unhandled error: ${paymentIntent.status}"
                    confirmPromise?.reject(ConfirmPaymentErrorType.Unknown.toString(), errorMessage)
                    handleCardActionPromise?.reject(NextPaymentActionErrorType.Unknown.toString(), errorMessage)
                  }
                }
              }

              override fun onError(e: Exception) {
                confirmPromise?.reject(ConfirmPaymentErrorType.Failed.toString(), e.toString())
                handleCardActionPromise?.reject(NextPaymentActionErrorType.Failed.toString(), e.toString())
              }
            })

        paymentSheetFragment?.activity?.activityResultRegistry?.dispatchResult(requestCode, resultCode, data)
        googlePayFragment?.activity?.activityResultRegistry?.dispatchResult(requestCode, resultCode, data)

            try {
              val result = AddPaymentMethodActivityStarter.Result.fromIntent(data)
              if (data?.getParcelableExtra<Parcelable>("extra_activity_result") != null) {
                onFpxPaymentMethodResult(result)
              }
            } catch (e: java.lang.Exception) {
              Log.d("Error", e.localizedMessage)
            }
          }
        }
      }
    }
  }

  init {
    reactContext.addActivityEventListener(mActivityEventListener);
  }

  private fun sendEvent(reactContext: ReactContext,
                        eventName: String,
                        @Nullable params: WritableMap) {
    reactContext
      .getJSModule(RCTDeviceEventEmitter::class.java)
      .emit(eventName, params)
  }

  private fun handleGooglePayResult(data: Intent) {
    val paymentData = PaymentData.getFromIntent(data) ?: return
    val paymentDataJson = JSONObject(paymentData.toJson())


    CoroutineScope(EmptyCoroutineContext).launch {
      runCatching {
        stripe.createPaymentMethod(
          PaymentMethodCreateParams.createFromGooglePay(paymentDataJson)
        )
      }.fold(
        onSuccess = {
          getPaymentMethodIdPromise?.resolve(it.id)
        },
        onFailure = {
          getPaymentMethodIdPromise?.reject("Exception while creating PaymentMethod", it)
          Log.e("HGPR", "Exception while creating PaymentMethod", it)
        }
      )
    }
  }

  private fun configure3dSecure(params: ReadableMap) {
    val stripe3dsConfigBuilder = PaymentAuthConfig.Stripe3ds2Config.Builder()
    if (params.hasKey("timeout")) stripe3dsConfigBuilder.setTimeout(params.getInt("timeout"))
    val uiCustomization = mapToUICustomization(params)

    PaymentAuthConfig.init(
      PaymentAuthConfig.Builder()
        .set3ds2Config(
          stripe3dsConfigBuilder
            .setUiCustomization(uiCustomization)
            .build()
        )
        .build()
    )
  }

  private val googlePayReceiver: BroadcastReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent) {
      if (intent.action == ON_GOOGLE_PAY_FRAGMENT_CREATED) {
        googlePayFragment = (currentActivity as AppCompatActivity).supportFragmentManager.findFragmentByTag("google_pay_launch_fragment") as GooglePayFragment
      }
      if (intent.action == ON_INIT_GOOGLE_PAY) {
        val isReady = intent.extras?.getBoolean("isReady") ?: false

        if (isReady) {
          initGooglePayPromise?.resolve(WritableNativeMap())
        } else {
          initGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), "Google Pay is not available on this device"))
        }
      }
      if (intent.action == ON_GOOGLE_PAYMENT_METHOD_RESULT) {
        intent.extras?.getString("error")?.let {
          presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), it))
          return
        }
        when (val result = intent.extras?.getParcelable<GooglePayPaymentMethodLauncher.Result>("paymentResult")) {
          is GooglePayPaymentMethodLauncher.Result.Completed -> {
            presentGooglePayPromise?.resolve(createResult("paymentMethod", mapFromPaymentMethod(result.paymentMethod)))
          }
          GooglePayPaymentMethodLauncher.Result.Canceled -> {
            presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), "Google Pay has been canceled"))
          }
          is GooglePayPaymentMethodLauncher.Result.Failed -> {
            presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), result.error))
          }
        }
      }
      if (intent.action == ON_GOOGLE_PAY_RESULT) {
        intent.extras?.getString("error")?.let {
          presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), it))
          return
        }
        when (val result = intent.extras?.getParcelable<GooglePayLauncher.Result>("paymentResult")) {
          GooglePayLauncher.Result.Completed -> {
            presentGooglePayPromise?.resolve(WritableNativeMap())
          }
          GooglePayLauncher.Result.Canceled -> {
            presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), "Google Pay has been canceled"))
          }
          is GooglePayLauncher.Result.Failed -> {
            presentGooglePayPromise?.resolve(createError(GooglePayErrorType.Failed.toString(), result.error))
          }
        }
      }
    }
  }

  private val mPaymentSheetReceiver: BroadcastReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent) {
      if (intent.action == ON_FRAGMENT_CREATED) {
        paymentSheetFragment = (currentActivity as AppCompatActivity).supportFragmentManager.findFragmentByTag("payment_sheet_launch_fragment") as PaymentSheetFragment
      }
      if (intent.action == ON_PAYMENT_RESULT_ACTION) {
        when (val result = intent.extras?.getParcelable<PaymentSheetResult>("paymentResult")) {
          is PaymentSheetResult.Canceled -> {
            val message = "The payment has been canceled"
            confirmPaymentSheetPaymentPromise?.resolve(createError(PaymentSheetErrorType.Canceled.toString(), message))
            presentPaymentSheetPromise?.resolve(createError(PaymentSheetErrorType.Canceled.toString(), message))
          }
          is PaymentSheetResult.Failed -> {
            confirmPaymentSheetPaymentPromise?.resolve(createError(PaymentSheetErrorType.Failed.toString(), result.error))
            presentPaymentSheetPromise?.resolve(createError(PaymentSheetErrorType.Failed.toString(), result.error))
          }
          is PaymentSheetResult.Completed -> {
            confirmPaymentSheetPaymentPromise?.resolve(WritableNativeMap())
            presentPaymentSheetPromise?.resolve(WritableNativeMap())
          }
        }
      } else if (intent.action == ON_PAYMENT_OPTION_ACTION) {
        val label = intent.extras?.getString("label")
        val image = intent.extras?.getString("image")

        if (label != null && image != null) {
          val option: WritableMap = WritableNativeMap()
          option.putString("label", label)
          option.putString("image", image)
          presentPaymentSheetPromise?.resolve(createResult("paymentOption", option))
        } else {
          presentPaymentSheetPromise?.resolve(WritableNativeMap())
        }
        presentPaymentSheetPromise = null
      }
      else if (intent.action == ON_INIT_PAYMENT_SHEET) {
        initPaymentSheetPromise?.resolve(WritableNativeMap())
      } else if (intent.action == ON_CONFIGURE_FLOW_CONTROLLER) {
        val label = intent.extras?.getString("label")
        val image = intent.extras?.getString("image")

        if (label != null && image != null) {
          val option: WritableMap = WritableNativeMap()
          option.putString("label", label)
          option.putString("image", image)
          initPaymentSheetPromise?.resolve(createResult("paymentOption", option))
        } else {
          initPaymentSheetPromise?.resolve(WritableNativeMap())
        }
      }
    }
  }

  @ReactMethod
  fun initialise(params: ReadableMap, promise: Promise) {
    val publishableKey = getValOr(params, "publishableKey", null) as String
    val appInfo = getMapOrNull(params, "appInfo") as ReadableMap
    this.stripeAccountId = getValOr(params, "stripeAccountId", null)
    val urlScheme = getValOr(params, "urlScheme", null)
    val setUrlSchemeOnAndroid = getBooleanOrFalse(params, "setUrlSchemeOnAndroid")
    val ttApiKey = getValOr(params, "ttApiKey", "")
    val ttApiVersion = getValOr(params, "ttApiVersion")
    val googlePayEnvironment = getValOr(params, "googlePayEnvironment", null)
    showNativePay = getBooleanOrFalse(params, "showNativePay")

    this.urlScheme = if (setUrlSchemeOnAndroid) urlScheme else null

    getMapOrNull(params, "threeDSecureParams")?.let {
      configure3dSecure(it)
    }

    this.publishableKey = publishableKey

    val name = getValOr(appInfo, "name", "") as String
    val partnerId = getValOr(appInfo, "partnerId", "")
    val version = getValOr(appInfo, "version", "")

    val url = getValOr(appInfo, "url", "")
    Stripe.appInfo = AppInfo.create(name, version, url, partnerId)
    stripe = Stripe(reactApplicationContext, publishableKey, stripeAccountId)

    PaymentConfiguration.init(reactApplicationContext, publishableKey, stripeAccountId)
    
    googlePayHelper = GooglePayHelper(
      currentActivity as AppCompatActivity,
      GooglePayConfig(reactApplicationContext).tokenizationSpecification,
      if (googlePayEnvironment.equals("test")) WalletConstants.ENVIRONMENT_TEST else WalletConstants.ENVIRONMENT_PRODUCTION
      )

    this.currentActivity?.registerReceiver(mPaymentSheetReceiver, IntentFilter(ON_PAYMENT_RESULT_ACTION));
    this.currentActivity?.registerReceiver(mPaymentSheetReceiver, IntentFilter(ON_PAYMENT_OPTION_ACTION));
    this.currentActivity?.registerReceiver(mPaymentSheetReceiver, IntentFilter(ON_CONFIGURE_FLOW_CONTROLLER));
    this.currentActivity?.registerReceiver(mPaymentSheetReceiver, IntentFilter(ON_FRAGMENT_CREATED));
    this.currentActivity?.registerReceiver(mPaymentSheetReceiver, IntentFilter(ON_INIT_PAYMENT_SHEET));

    this.currentActivity?.registerReceiver(googlePayReceiver, IntentFilter(ON_GOOGLE_PAY_FRAGMENT_CREATED))
    this.currentActivity?.registerReceiver(googlePayReceiver, IntentFilter(ON_INIT_GOOGLE_PAY))
    this.currentActivity?.registerReceiver(googlePayReceiver, IntentFilter(ON_GOOGLE_PAY_RESULT))
    this.currentActivity?.registerReceiver(googlePayReceiver, IntentFilter(ON_GOOGLE_PAYMENT_METHOD_RESULT))

    ttKeyProvider.setTTApiKey(ttApiKey)
    ttKeyProvider.setTTApiVersion(ttApiVersion)
    isReadyToPay()
    promise.resolve(null)
  }

  private fun isReadyToPay() {
    googlePayHelper.paymentsClient.isReadyToPay(googlePayHelper.createIsReadyToPayRequest())
      .addOnCompleteListener { task ->
        try {
          isSupportsGooglePay = task.isSuccessful
        } catch (exception: ApiException) {
        }
      }
  }

  @ReactMethod
  fun payWithGoogle() {
    AutoResolveHelper.resolveTask(
      googlePayHelper.paymentsClient.loadPaymentData(googlePayHelper.createPaymentDataRequest()),
      currentActivity as AppCompatActivity,
      LOAD_PAYMENT_DATA_REQUEST_CODE
    )
  }

  companion object {
    private const val LOAD_PAYMENT_DATA_REQUEST_CODE = 53
  }

  @ReactMethod
  fun setSessionId(_sessionId: String) {
    ttKeyProvider?.setSessionId(_sessionId);
  }

  @ReactMethod
  fun initCustomerContext(promise: Promise) {
    ttKeyProvider.setPromise(promise)
      CustomerSession.initCustomerSession(
        reactApplicationContext,
        ttKeyProvider,
        true
      )
  }

  @ReactMethod
  fun showPaymentOptionsModal(cartTotal: Double) {
    UiThreadUtil.runOnUiThread {
      val activity = currentActivity as AppCompatActivity

      paymentSession = PaymentSession(
        activity,
        PaymentSessionConfig.Builder()
          .setShippingInfoRequired(false)
          .setShouldShowGooglePay(showNativePay && isSupportsGooglePay)
          .setShippingMethodsRequired(false)
          .build()
      )
      paymentSession.setCartTotal(cartTotal.toLong())
      googlePayHelper.totalPrice = cartTotal.toString()

      paymentSession.init(
        object : PaymentSession.PaymentSessionListener {
          override fun onCommunicatingStateChanged(isCommunicating: Boolean) {
            // update UI, such as hiding or showing a progress bar
          }

          override fun onError(errorCode: Int, errorMessage: String) {
            // handle error
          }

          override fun onPaymentSessionDataChanged(data: PaymentSessionData) {
            val paymentMethod: PaymentMethod? = data.paymentMethod
            if (paymentMethod !== null || data.useGooglePay) {

              lastIsGooglePayUsed = data.useGooglePay
              lastPaymentMethodId = paymentMethod?.id
              val params = Arguments.createMap()
              params.putString("methodId", paymentMethod?.id)
              params.putString("label", ""+paymentMethod?.card?.brand+" "+paymentMethod?.card?.last4)
              params.putString("image", "")
              params.putBoolean("useGooglePay", data.useGooglePay)
              params.putBoolean("useApplePay", false)

              sendEvent(reactApplicationContext, "onDidSelectPaymentMethod", params)
            }
          }
        }
      )

      paymentSession.presentPaymentMethodSelection()
    }
  }

  @ReactMethod
  fun getPaymentMethodId(promise: Promise) {
    if(!lastIsGooglePayUsed) {
      promise.resolve(lastPaymentMethodId)
    } else {
      getPaymentMethodIdPromise = promise
      payWithGoogle()
    }
  }

  @ReactMethod
  fun initPaymentSheet(params: ReadableMap, promise: Promise) {
    val activity = currentActivity as AppCompatActivity?

    if (activity == null) {
      promise.resolve(createError("Failed", "Activity doesn't exist"))
      return
    }

    this.initPaymentSheetPromise = promise

    val fragment = PaymentSheetFragment().also {
      val bundle = toBundleObject(params)
      it.arguments = bundle
    }
    activity.supportFragmentManager.beginTransaction()
      .add(fragment, "payment_sheet_launch_fragment")
      .commit()
  }

  @ReactMethod
  fun presentPaymentSheet(promise: Promise) {
    this.presentPaymentSheetPromise = promise
    paymentSheetFragment?.present()
  }

  @ReactMethod
  fun confirmPaymentSheetPayment(promise: Promise) {
    this.confirmPaymentSheetPaymentPromise = promise
    paymentSheetFragment?.confirmPayment()
  }

  private fun payWithFpx() {
    AddPaymentMethodActivityStarter(currentActivity as AppCompatActivity)
      .startForResult(AddPaymentMethodActivityStarter.Args.Builder()
        .setPaymentMethodType(PaymentMethod.Type.Fpx)
        .build()
      )
  }

  private fun onFpxPaymentMethodResult(result: AddPaymentMethodActivityStarter.Result) {
    when (result) {
      is AddPaymentMethodActivityStarter.Result.Success -> {
        val activity = currentActivity as ComponentActivity

        stripe.confirmPayment(activity,
          ConfirmPaymentIntentParams.createWithPaymentMethodId(
            result.paymentMethod.id!!,
            confirmPaymentClientSecret!!,
          ));
      }
      is AddPaymentMethodActivityStarter.Result.Failure -> {
        confirmPromise?.resolve(createError(ConfirmPaymentErrorType.Failed.toString(), result.exception))
      }
      is AddPaymentMethodActivityStarter.Result.Canceled -> {
        confirmPromise?.resolve(createError(ConfirmPaymentErrorType.Canceled.toString(), "The payment has been canceled"))
      }
    }
    this.confirmPaymentClientSecret = null
  }

  @ReactMethod
  fun createPaymentMethod(data: ReadableMap, options: ReadableMap, promise: Promise) {
    val cardParams = (cardFieldView?.cardParams ?: cardFormView?.cardParams) ?: run {
      promise.resolve(createError("Failed", "Card details not complete"))
      return
    }
    val cardAddress = cardFieldView?.cardAddress ?: cardFormView?.cardAddress

    val billingDetailsParams = mapToBillingDetails(getMapOrNull(data, "billingDetails"), cardAddress)

    val paymentMethodCreateParams = PaymentMethodCreateParams.create(cardParams, billingDetailsParams)
    stripe.createPaymentMethod(
      paymentMethodCreateParams,
      callback = object : ApiResultCallback<PaymentMethod> {
        override fun onError(error: Exception) {
          promise.resolve(createError("Failed", error))
        }

        override fun onSuccess(result: PaymentMethod) {
          val paymentMethodMap: WritableMap = mapFromPaymentMethod(result)
          promise.resolve(createResult("paymentMethod", paymentMethodMap))
        }
      })
  }

  @ReactMethod
  fun createToken(params: ReadableMap, promise: Promise) {
    val type = getValOr(params, "type", null)?.let {
      if (it != "Card") {
        promise.resolve(createError(CreateTokenErrorType.Failed.toString(), "$it type is not supported yet"))
        return
      }
    }
    val address = getMapOrNull(params, "address")

    val cardParamsMap = (cardFieldView?.cardParams ?: cardFormView?.cardParams)?.toParamMap() ?: run {
      promise.resolve(createError(CreateTokenErrorType.Failed.toString(), "Card details not complete"))
      return
    }

    val cardAddress = cardFieldView?.cardAddress ?: cardFormView?.cardAddress

    val cardParams = CardParams(
      number = cardParamsMap["number"] as String,
      expMonth = cardParamsMap["exp_month"] as Int,
      expYear = cardParamsMap["exp_year"] as Int,
      cvc = cardParamsMap["cvc"] as String,
      address = mapToAddress(address, cardAddress),
      name = getValOr(params, "name", null)
    )
    runBlocking {
      try {
        val token = stripe.createCardToken(
          cardParams = cardParams,
          stripeAccountId = stripeAccountId
        )
        promise.resolve(createResult("token", mapFromToken(token)))
      } catch (e: Exception) {
        promise.resolve(createError(CreateTokenErrorType.Failed.toString(), e.message))
      }
    }
  }

  @ReactMethod
  fun createTokenForCVCUpdate(cvc: String, promise: Promise) {
    stripe.createCvcUpdateToken(
      cvc,
      callback = object : ApiResultCallback<Token> {
        override fun onSuccess(result: Token) {
          val tokenId = result.id
          val res = WritableNativeMap()
          res.putString("tokenId", tokenId)
          promise.resolve(res)
        }

        override fun onError(error: Exception) {
          promise.resolve(createError("Failed", error))
        }
      }
    )
  }

  @ReactMethod
  fun handleCardAction(paymentIntentClientSecret: String, promise: Promise) {
    val activity = currentActivity as ComponentActivity
    if (activity != null) {
      handleCardActionPromise = promise
      stripe.handleNextActionForPayment(activity, paymentIntentClientSecret)
    }
  }

  private fun payWithWeChatPay(paymentIntentClientSecret: String, appId: String) {
    val activity = currentActivity as ComponentActivity

    activity.lifecycleScope.launch {
      stripe.createPaymentMethod(PaymentMethodCreateParams.createWeChatPay()).id?.let { paymentMethodId ->
        val confirmPaymentIntentParams =
          ConfirmPaymentIntentParams.createWithPaymentMethodId(
            paymentMethodId = paymentMethodId,
            clientSecret = paymentIntentClientSecret,
            paymentMethodOptions = PaymentMethodOptionsParams.WeChatPay(
              appId
            )
          )
        stripe.confirmPayment(activity, confirmPaymentIntentParams)
      }
    }
  }

  @ReactMethod
  fun confirmPayment(paymentIntentClientSecret: String, params: ReadableMap, options: ReadableMap, promise: Promise) {
    confirmPromise = promise
    confirmPaymentClientSecret = paymentIntentClientSecret

    val paymentMethodType = getValOr(params, "type")?.let { mapToPaymentMethodType(it) } ?: run {
      promise.resolve(createError(ConfirmPaymentErrorType.Failed.toString(), "You must provide paymentMethodType"))
      return
    }

    val testOfflineBank = getBooleanOrFalse(params, "testOfflineBank")

    if (paymentMethodType == PaymentMethod.Type.Fpx && !testOfflineBank) {
      payWithFpx()
      return
    }

//    if (paymentMethodType == PaymentMethod.Type.WeChatPay) {
//      val appId = getValOr(params, "appId") ?: run {
//        promise.resolve(createError("Failed", "You must provide appId"))
//        return
//      }
//      payWithWeChatPay(paymentIntentClientSecret, appId)
//
//      return
//    }

    val factory = PaymentMethodCreateParamsFactory(paymentIntentClientSecret, params, cardFieldView, cardFormView)

    try {
      val activity = currentActivity as ComponentActivity
      val confirmParams = factory.createConfirmParams(paymentMethodType)
      confirmParams.shipping = mapToShippingDetails(getMapOrNull(params, "shippingDetails"))
      stripe.confirmPayment(activity, confirmParams)
    } catch (error: PaymentMethodCreateParamsException) {
      promise.resolve(createError(ConfirmPaymentErrorType.Failed.toString(), error))
    }
  }

  @ReactMethod
  fun retrievePaymentIntent(clientSecret: String, promise: Promise) {
    AsyncTask.execute {
      val paymentIntent = stripe.retrievePaymentIntentSynchronous(clientSecret)
      paymentIntent?.let {
        promise.resolve(createResult("paymentIntent", mapFromPaymentIntentResult(it)))
      } ?: run {
        promise.resolve(createError(RetrievePaymentIntentErrorType.Unknown.toString(), "Failed to retrieve the PaymentIntent"))
      }
    }
  }

  @ReactMethod
  fun retrieveSetupIntent(clientSecret: String, promise: Promise) {
    AsyncTask.execute {
      val setupIntent = stripe.retrieveSetupIntentSynchronous(clientSecret)
      setupIntent?.let {
        promise.resolve(createResult("setupIntent", mapFromSetupIntentResult(it)))
      } ?: run {
        promise.resolve(createError(RetrieveSetupIntentErrorType.Unknown.toString(), "Failed to retrieve the SetupIntent"))
      }
    }
  }

  @ReactMethod
  fun confirmSetupIntent(setupIntentClientSecret: String, params: ReadableMap, options: ReadableMap, promise: Promise) {
    confirmSetupIntentPromise = promise

    val paymentMethodType = getValOr(params, "type")?.let { mapToPaymentMethodType(it) } ?: run {
      promise.resolve(createError(ConfirmPaymentErrorType.Failed.toString(), "You must provide paymentMethodType"))
      return
    }

    val factory = PaymentMethodCreateParamsFactory(setupIntentClientSecret, params, cardFieldView, cardFormView)

    try {
      val activity = currentActivity as ComponentActivity
      val confirmParams = factory.createSetupParams(paymentMethodType)
      stripe.confirmSetupIntent(activity, confirmParams)
    } catch (error: PaymentMethodCreateParamsException) {
      promise.resolve(createError(ConfirmPaymentErrorType.Failed.toString(), error))
    }
  }

  @ReactMethod
  fun initGooglePay(params: ReadableMap, promise: Promise) {
    val activity = currentActivity as AppCompatActivity
    val fragment = GooglePayFragment().also {
      val bundle = toBundleObject(params)
      it.arguments = bundle
    }

    initGooglePayPromise = promise

    activity.supportFragmentManager.beginTransaction()
      .add(fragment, "google_pay_launch_fragment")
      .commit()
  }

  @ReactMethod
  fun presentGooglePay(params: ReadableMap, promise: Promise) {
    val clientSecret = getValOr(params, "clientSecret") ?: run {
      promise.resolve(createError(GooglePayErrorType.Failed.toString(), "you must provide clientSecret"))
      return
    }
    presentGooglePayPromise = promise
    if (getBooleanOrFalse(params, "forSetupIntent")) {
      val currencyCode = getValOr(params, "currencyCode") ?: run {
        promise.resolve(createError(GooglePayErrorType.Failed.toString(), "you must provide currencyCode"))
        return
      }
      googlePayFragment?.presentForSetupIntent(clientSecret, currencyCode)
    } else {
      googlePayFragment?.presentForPaymentIntent(clientSecret)
    }
  }

  @ReactMethod
  fun createGooglePayPaymentMethod(params: ReadableMap, promise: Promise) {
    val currencyCode = getValOr(params, "currencyCode", null) ?: run {
      promise.resolve(createError(GooglePayErrorType.Failed.toString(), "you must provide currencyCode"))
      return
    }
    val amount = getIntOrNull(params, "amount") ?: run {
      promise.resolve(createError(GooglePayErrorType.Failed.toString(), "you must provide amount"))
      return
    }
    presentGooglePayPromise = promise
    googlePayFragment?.createPaymentMethod(currencyCode, amount)
  }


  /// Check paymentIntent.nextAction is voucher-based payment method.
  /// If it's voucher-based, the paymentIntent status stays in requiresAction until the voucher is paid or expired.
  /// Currently only OXXO payment is voucher-based.
  private fun isPaymentIntentNextActionVoucherBased(nextAction: StripeIntent.NextActionType?): Boolean {
    nextAction?.let {
      return it == StripeIntent.NextActionType.DisplayOxxoDetails
    }
    return false
  }

  companion object {
    const val NAME = "StripeSdk"
  }
}
