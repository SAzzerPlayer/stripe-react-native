package com.reactnativestripesdk

import okhttp3.ResponseBody
import retrofit2.http.FieldMap
import retrofit2.http.FormUrlEncoded
import retrofit2.http.Header
import retrofit2.http.POST

/**
 * A Retrofit service used to communicate with a server.
 */
interface BackendApi {

  @FormUrlEncoded
  @POST("stripe_ephemeral_key")
  suspend fun createEphemeralKey(@Header("Token-Transit-Api-Key") ttApiKey: String? = "",
                                 @Header("Token-Transit-Api-Version") ttApiVersion: String? = "",
                                 @Header("Cookie") sessionCookie: String,
                                 @FieldMap apiVersionMap: HashMap<String, String>): ResponseBody

}
