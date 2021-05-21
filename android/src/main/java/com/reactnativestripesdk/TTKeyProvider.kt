package com.reactnativestripesdk

import androidx.annotation.Size
import com.facebook.react.bridge.Promise
import com.stripe.android.EphemeralKeyProvider
import com.stripe.android.EphemeralKeyUpdateListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

internal class TTKeyProvider: EphemeralKeyProvider {

  private val backendApi = BackendApiFactory().create()

  private var sessionId = ""
  private var ttApiKey = ""
  private var ttApiVersion = ""

  private lateinit var promise: Promise

  fun setSessionId(_sessionId: String) {
    sessionId = _sessionId
  }

  fun setPromise(_promise: Promise) {
    promise = _promise
  }

  fun setTTApiKey(_ttApiKey: String?) {
    if (_ttApiKey != null) {
      ttApiKey = _ttApiKey
    }
  }

  fun setTTApiVersion(_ttApiVersion: String?) {
    if (_ttApiVersion != null) {
      ttApiVersion = _ttApiVersion
    }
  }

  override fun createEphemeralKey(
    @Size(min = 4) apiVersion: String,
    keyUpdateListener: EphemeralKeyUpdateListener
  ) {
    CoroutineScope(EmptyCoroutineContext).launch {
      val response =
        kotlin.runCatching {
          backendApi
            .createEphemeralKey(ttApiKey,
              ttApiVersion,
              "user_session_id=$sessionId",
              hashMapOf("stripe_api_version" to apiVersion))
            .string()
        }

      withContext(Dispatchers.Main) {
        response.fold(
          onSuccess = {
            promise.resolve(true)
            keyUpdateListener.onKeyUpdate(it)
          },
          onFailure = {
            promise.reject("3", it.message.orEmpty())
            keyUpdateListener
              .onKeyUpdateFailure(0, it.message.orEmpty())
          }
        )
      }
    }
  }
}
