package com.reactnativestripesdk

import androidx.appcompat.app.AppCompatActivity
import com.google.android.gms.wallet.*
import com.stripe.android.GooglePayConfig
import org.json.JSONArray
import org.json.JSONObject

class GooglePayHelper(private val activity: AppCompatActivity,
                      private val tokenSpecs: JSONObject,
                      private val env: Int) {

  var totalPrice: String? = ""

  val paymentsClient: PaymentsClient by lazy {
    Wallet.getPaymentsClient(
      activity,
      Wallet.WalletOptions.Builder()
        .setEnvironment(env)
        .build()
    )
  }

  fun createPaymentDataRequest(): PaymentDataRequest {
    val cardPaymentMethod = JSONObject()
      .put("type", "CARD")
      .put(
        "parameters",
        JSONObject()
          .put("allowedAuthMethods", JSONArray()
            .put("PAN_ONLY")
            .put("CRYPTOGRAM_3DS"))
          .put("allowedCardNetworks",
            JSONArray()
              .put("AMEX")
              .put("DISCOVER")
              .put("MASTERCARD")
              .put("VISA"))

          // require billing address
          .put("billingAddressRequired", true)
          .put(
            "billingAddressParameters",
            JSONObject()
              // require full billing address
              .put("format", "MIN")

              // require phone number
              .put("phoneNumberRequired", true)
          )
      )
      .put(
        "tokenizationSpecification",
        tokenSpecs
      )

    // create PaymentDataRequest
    val paymentDataRequest = JSONObject()
      .put("apiVersion", 2)
      .put("apiVersionMinor", 0)
      .put("allowedPaymentMethods",
        JSONArray().put(cardPaymentMethod))
      .put("transactionInfo", JSONObject()
        .put("totalPrice", totalPrice)
        .put("totalPriceStatus", "FINAL")
        .put("currencyCode", "USD")
      )
      .put("merchantInfo", JSONObject()
        .put("merchantName", "Example Merchant"))

      // require email address
      .put("emailRequired", true)
      .toString()

    return PaymentDataRequest.fromJson(paymentDataRequest)
  }
  fun createIsReadyToPayRequest(): IsReadyToPayRequest {
    return IsReadyToPayRequest.fromJson(
      JSONObject()
        .put("apiVersion", 2)
        .put("apiVersionMinor", 0)
        .put(
          "allowedPaymentMethods",
          JSONArray().put(
            JSONObject()
              .put("type", "CARD")
              .put(
                "parameters",
                JSONObject()
                  .put(
                    "allowedAuthMethods",
                    JSONArray()
                      .put("PAN_ONLY")
                      .put("CRYPTOGRAM_3DS")
                  )
                  .put(
                    "allowedCardNetworks",
                    JSONArray()
                      .put("AMEX")
                      .put("DISCOVER")
                      .put("MASTERCARD")
                      .put("VISA")
                  )
              )
          )
        )
        .toString()
    )
  }
}
