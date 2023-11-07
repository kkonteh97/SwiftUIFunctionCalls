//
//  OpenAIService.swift
//  MediumFunctionCalls
//
//  Created by kemo konteh on 11/6/23.
//

import Foundation
import Alamofire
import Combine

enum Constants {
    static let OpenAIAPIKey = "YOUR_API_KEY"
}

// We would then include this function definition within our `OpenAIParameters` struct
// under the `functions` field when making the API call.
// …
// we have an OpenAIParameters struct that we use to encode our request body
// in it we define our model, messages, functions, function_call, and max_tokens

struct OpenAIParameters: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let functions: [Function]
    let function_call: String
    let max_tokens: Int
}
// the Function struct is used to define our functions. The name of the function a quick decription of what it does and the parameters it takes in

struct Function: Codable {
    let name: String
    let description: String
    let parameters: Parameters
}
// for parameters we define the type, properties, and the parameters that are required
struct Parameters: Codable {
    let type: String
    let properties: [String: Property]
    let required: [String]
}

struct Property: Codable {
    let type: String
    let description: String?
}

struct OpenAIResponse: Decodable {
    let id: String
    let choices: [OpenAIResponseChoice]
}

struct OpenAIResponseChoice: Decodable {
    let index: Int
    let message: OpenAIMessage
    let finish_reason: String
}
// we include the function_call in our OpenAIMessage struct which is an optional and will be used when the model wants
// to call a function
struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let function_call: FunctionCall?
    let name: String?

    init(role: String, content: String?, function_call: FunctionCall? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.function_call = function_call
        self.name = name
    }
}

// if a function is being called we define the name of the function and the arguments it takes in                                9
struct FunctionCall: Codable {
    let name: String
    let arguments: String
}
// for our example function we take in a location and a unit, the unit is optional
struct Arguments: Decodable {
    let location: String
    let unit: String?
}

let getCurrentWeatherFunction =  Function(name: "get_current_weather",
                                          description: "Get the current weather in a given location",
                                          parameters: Parameters(type: "object",
                                                                 properties: ["location":
                                                                                Property(type: "integer",
                                                                                         description: "The city and state, e.g. San Francisco, CA"),
                                                                              "unit":
                                                                                Property(type: "string",
                                                                                         description: "The unit of measurement, e.g. fahrenheit or celsius")
                                                                             ],
                                                                 required: ["location"]
                                                                )
)

class OpenAIService {
    let baseUrl = "https://api.openai.com/v1/chat/completions"

    var isLoading: Bool = false
    // we keep track of the messages we send to the model, so that the model has context of the conversation
    var messages: [OpenAIMessage] = []

    func makeRequest(message: OpenAIMessage) -> AnyPublisher<OpenAIResponse, Error> {
        messages.append(message)
        let functions: [Function] = [getCurrentWeatherFunction] // Include our defined functions
        let parameters = OpenAIParameters(
            model: "gpt-3.5-turbo-0613",
            messages: messages,
            functions: functions,
            function_call: "auto",
            max_tokens: 256
        )
        let headers: HTTPHeaders = ["Authorization" : "Bearer \(Constants.OpenAIAPIKey)"]
        // Networking logic using Alamofire and Combine
        return Future { [weak self] promise in
            self?.performNetworkRequest(with: parameters, headers: headers, promise: promise)
        }
        .eraseToAnyPublisher()
    }

    private func performNetworkRequest(with parameters: OpenAIParameters,
                                       headers: HTTPHeaders,
                                       promise: @escaping (Result<OpenAIResponse, Error>) -> Void) {
        AF.request(baseUrl,
                   method: .post,
                   parameters: parameters,
                   encoder: .json,
                   headers: headers
        )
        .validate() // Ensures we only proceed with valid HTTP responses
        .responseDecodable(of: OpenAIResponse.self) { response in
            switch response.result {
            case .success(let result):
                promise(.success(result))
            case .failure(let error):
                promise(.failure(error))
            }
        }
    }

    func handleFunctionCall(functionCall: FunctionCall, completion: @escaping (Result<String, Error>) -> Void) {
        self.messages.append(OpenAIMessage(role: "assistant", content: "", function_call: functionCall))

        // Map the function name to the actual function implementation
        let availableFunctions: [String: (String, String?) -> String] = ["get_current_weather": getCurrentWeather]

        // Attempt to execute the named function with provided arguments
        if let functionToCall = availableFunctions[functionCall.name],
           let jsonData = functionCall.arguments.data(using: .utf8) {
            do {
                let arguments = try JSONDecoder().decode(Arguments.self, from: jsonData)
                let functionResponse = functionToCall(arguments.location, arguments.unit)
                completion(.success(functionResponse))
            } catch {
                completion(.failure(error))
            }
        } else {
            let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Function not found or supported."])
            completion(.failure(error))
        }
    }
}

// Example dummy function hard coded to return the same weather
// In production, this could be your backend API or an external API
func getCurrentWeather(location: String, unit: String?) -> String {
    let weatherInfo: [String: Any] = [
        "location": location,
        "temperature": "72",
        "unit": unit ?? "fahrenheit",
        "forecast": ["sunny", "windy"],
    ]
    let jsonData = try? JSONSerialization.data(withJSONObject: weatherInfo, options: .prettyPrinted)
    return String(data: jsonData!, encoding: .utf8)!
}


//    curl https://api.openai.com/v1/chat/completions -u :$OPENAI_API_KEY -H 'Content-Type: application/json' -d '{
//      "model": "gpt-3.5-turbo-0613",
//      "messages": [
//        {"role": "user", "content": "What is the weather like in Boston?"},
//        {"role": "assistant", "content": null, "function_call": {"name": "get_current_weather", "arguments": "{ \"location\": \"Boston, MA\"}"}},
//        {"role": "function", "name": "get_current_weather", "content": "{\"temperature\": "22", \"unit\": \"celsius\", \"description\": \"Sunny\"}"}
//      ],
//      "functions": [
//        {
//          "name": "get_current_weather",
//          "description": "Get the current weather in a given location",
//          "parameters": {
//            "type": "object",
//            "properties": {
//              "location": {
//                "type": "string",
//                "description": "The city and state, e.g. San Francisco, CA"
//              },
//              "unit": {
//                "type": "string",
//                "enum": ["celsius", "fahrenheit"]
//              }
//            },
//            "required": ["location"]
//          }
//        }
//      ]
//    }'
