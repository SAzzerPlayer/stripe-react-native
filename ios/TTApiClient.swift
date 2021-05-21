//
//  TTApiClient.swift
//  StripeSdk
//
//  Created by Дмитрий Яценко on 16.05.2021.
//  Copyright © 2021 Facebook. All rights reserved.
//

import Foundation
import PassKit
import Stripe

class TTApiClient: NSObject, STPCustomerEphemeralKeyProvider {
    enum APIError: Error {
            case unknown

            var localizedDescription: String {
                switch self {
                case .unknown:
                    return "Unknown error"
                }
            }
        }

    static let sharedClient = TTApiClient()

    var baseURLString: String?
    var ttApiKey: String?
    var ttApiVersion: String?
    var sessionId: String?

    var resolve: RCTPromiseResolveBlock?
    var reject: RCTPromiseRejectBlock?

    var baseURL: URL {
        if let urlString = self.baseURLString, let url = URL(string: urlString) {
            return url
        } else {
            fatalError()
        }
    }

    func createCustomerKey(
            withAPIVersion apiVersion: String, completion: @escaping STPJSONResponseCompletionBlock
        ) {
            let url = self.baseURL.appendingPathComponent("stripe_ephemeral_key")
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            urlComponents.queryItems = [URLQueryItem(name: "stripe_api_version", value: apiVersion)]
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "POST"
            request.setValue(self.ttApiKey, forHTTPHeaderField: "Token-Transit-Api-Key")
            request.setValue(self.ttApiVersion, forHTTPHeaderField: "Token-Transit-Api-Version")
            request.setValue("user_session_id="+self.sessionId!, forHTTPHeaderField: "Cookie")

            let task = URLSession.shared.dataTask(
                with: request,
                completionHandler: { (data, response, error) in
                    guard let response = response as? HTTPURLResponse,
                        response.statusCode == 200,
                        let data = data,
                        let json =
                            ((try? JSONSerialization.jsonObject(with: data, options: [])
                            as? [String: Any]) as [String: Any]??)
                    else {
                        self.reject!("3", "Can't get ephermal key", nil)
                        completion(nil, error)
                        return
                    }
                    completion(json, nil)
                    self.resolve!(true)
                })
            task.resume()
        }
}
