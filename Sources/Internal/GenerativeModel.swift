// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// A type that represents a remote multimodal model (like Gemini), with the ability to generate
/// content based on various input types.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public final class GenerativeModel {
  /// The resource name of the model in the backend; has the format "models/model-name".
  let modelResourceName: String

  /// The backing service responsible for sending and receiving model requests to the backend.
  let generativeAIService: GenerativeAIService

  /// Configuration parameters used for the MultiModalModel.
  let generationConfig: GenerationConfig?

  /// The safety settings to be used for prompts.
  let safetySettings: [SafetySetting]?

  /// Configuration parameters for sending requests to the backend.
  let requestOptions: RequestOptions

  /// The designated initializer for this class.
  public init(modelResourceName: String,
              apiKey: String,
              generationConfig: GenerationConfig? = nil,
              safetySettings: [SafetySetting]? = nil,
              requestOptions: RequestOptions,
              urlSession: URLSession) {
    self.modelResourceName = modelResourceName
    generativeAIService = GenerativeAIService(apiKey: apiKey, urlSession: urlSession)
    self.generationConfig = generationConfig
    self.safetySettings = safetySettings
    self.requestOptions = requestOptions

    Logging.default.info("""
    [GoogleGenerativeAI] Model \(
      modelResourceName,
      privacy: .public
    ) initialized. To enable additional logging, add \
    `\(Logging.enableArgumentKey, privacy: .public)` as a launch argument in Xcode.
    """)
    Logging.verbose.debug("[GoogleGenerativeAI] Verbose logging enabled.")
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: The generated content response from the model.
  /// - Throws: A ``GenerateContentError`` if the request failed.
  public func generateContent(_ content: [ModelContent]) async throws
    -> GenerateContentResponse {
    let generateContentRequest = GenerateContentRequest(model: modelResourceName,
                                                        contents: content,
                                                        generationConfig: generationConfig,
                                                        safetySettings: safetySettings,
                                                        isStreaming: false,
                                                        options: requestOptions)
    let response = try await generativeAIService.loadRequest(request: generateContentRequest)

    // Check the prompt feedback to see if the prompt was blocked.
    if response.promptFeedback?.blockReason != nil {
      throw InternalGenerativeAI.GenerateContentError.promptBlocked(response: response)
    }

    // Check to see if an error should be thrown for stop reason.
    if let reason = response.candidates.first?.finishReason, reason != .stop {
      throw InternalGenerativeAI.GenerateContentError.responseStoppedEarly(
        reason: reason,
        response: response
      )
    }

    return response
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: A stream wrapping content generated by the model or a ``GenerateContentError``
  ///     error if an error occurred.
  @available(macOS 12.0, *)
  public func generateContentStream(_ content: [ModelContent])
    -> AsyncThrowingStream<GenerateContentResponse, Error> {
    let generateContentRequest = GenerateContentRequest(model: modelResourceName,
                                                        contents: content,
                                                        generationConfig: generationConfig,
                                                        safetySettings: safetySettings,
                                                        isStreaming: true,
                                                        options: requestOptions)

    var responseIterator = generativeAIService.loadRequestStream(request: generateContentRequest)
      .makeAsyncIterator()
    return AsyncThrowingStream {
      let response = try await responseIterator.next()

      // The responseIterator will return `nil` when it's done.
      guard let response = response else {
        // This is the end of the stream! Signal it by sending `nil`.
        return nil
      }

      // Check the prompt feedback to see if the prompt was blocked.
      if response.promptFeedback?.blockReason != nil {
        throw InternalGenerativeAI.GenerateContentError.promptBlocked(response: response)
      }

      // If the stream ended early unexpectedly, throw an error.
      if let finishReason = response.candidates.first?.finishReason, finishReason != .stop {
        throw InternalGenerativeAI.GenerateContentError.responseStoppedEarly(
          reason: finishReason,
          response: response
        )
      } else {
        // Response was valid content, pass it along and continue.
        return response
      }
    }
  }

  /// Creates a new chat conversation using this model with the provided history.
  // TODO(andrewheard): Implement me
  // public func startChat(history: [ModelContent] = []) -> Chat {
  //   return Chat(model: self, history: history)
  // }

  /// Runs the model's tokenizer on the input content and returns the token count.
  ///
  /// - Parameter content: The input given to the model as a prompt.
  /// - Returns: The results of running the model's tokenizer on the input; contains
  /// ``CountTokensResponse/totalTokens``.
  /// - Throws: A ``CountTokensError`` if the tokenization request failed or the input content was
  /// invalid.
  public func countTokens(_ content: [ModelContent]) async throws
    -> CountTokensResponse {
    do {
      let countTokensRequest = CountTokensRequest(
        model: modelResourceName,
        contents: content,
        options: requestOptions
      )
      return try await generativeAIService.loadRequest(request: countTokensRequest)
    } catch {
      throw CountTokensError.internalError(underlying: error)
    }
  }

//  /// Returns a model resource name of the form "models/model-name" based on `name`.
//  private static func modelResourceName(name: String) -> String {
//    if name.contains("/") {
//      return name
//    } else {
//      return modelResourcePrefix + name
//    }
//  }
}

/// See ``GenerativeModel/countTokens(_:)-9spwl``.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public enum CountTokensError: Error {
  case internalError(underlying: Error)
}
