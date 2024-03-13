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
import InternalGenerativeAI

/// A type that represents a remote multimodal model (like Gemini), with the ability to generate
/// content based on various input types.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public final class GenerativeModel {
  // The prefix for a model resource in the Gemini API.
  private static let modelResourcePrefix = "models/"

  /// The resource name of the model in the backend; has the format "models/model-name".
  let modelResourceName: String

  let internalModel: InternalGenerativeAI.GenerativeModel

  /// Initializes a new remote model with the given parameters.
  ///
  /// - Parameters:
  ///   - name: The name of the model to use, e.g., `"gemini-1.0-pro"`; see
  ///     [Gemini models](https://ai.google.dev/models/gemini) for a list of supported model names.
  ///   - apiKey: The API key for your project.
  ///   - generationConfig: The content generation parameters your model should use.
  ///   - safetySettings: A value describing what types of harmful content your model should allow.
  ///   - requestOptions Configuration parameters for sending requests to the backend.
  public convenience init(name: String,
                          apiKey: String,
                          generationConfig: GenerationConfig? = nil,
                          safetySettings: [SafetySetting]? = nil,
                          requestOptions: RequestOptions = RequestOptions()) {
    self.init(
      name: name,
      apiKey: apiKey,
      generationConfig: generationConfig,
      safetySettings: safetySettings,
      requestOptions: requestOptions,
      urlSession: .shared
    )
  }

  /// The designated initializer for this class.
  init(name: String,
       apiKey: String,
       generationConfig: GenerationConfig? = nil,
       safetySettings: [SafetySetting]? = nil,
       requestOptions: RequestOptions = RequestOptions(),
       urlSession: URLSession) {
    modelResourceName = GenerativeModel.modelResourceName(name: name)

    Logging.default.info("""
    [GoogleGenerativeAI] Model \(
      name,
      privacy: .public
    ) initialized. To enable additional logging, add \
    `\(Logging.enableArgumentKey, privacy: .public)` as a launch argument in Xcode.
    """)
    Logging.verbose.debug("[GoogleGenerativeAI] Verbose logging enabled.")

    internalModel = InternalGenerativeAI.GenerativeModel(
      modelResourceName: modelResourceName,
      apiKey: apiKey,
      generationConfig: generationConfig?.toInternal(),
      safetySettings: safetySettings?.toInternal(),
      requestOptions: requestOptions.toInternal(),
      urlSession: urlSession
    )
  }

  /// Generates content from String and/or image inputs, given to the model as a prompt, that are
  /// representable as one or more ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for generating
  /// content from
  /// [zero-shot](https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting)
  /// or "direct" prompts. For
  /// [few-shot](https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting)
  /// prompts, see ``generateContent(_:)-58rm0``.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: The content generated by the model.
  /// - Throws: A ``GenerateContentError`` if the request failed.
  public func generateContent(_ parts: any ThrowingPartsRepresentable...)
    async throws -> GenerateContentResponse {
    return try await generateContent([ModelContent(parts: parts)])
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: The generated content response from the model.
  /// - Throws: A ``GenerateContentError`` if the request failed.
  public func generateContent(_ content: @autoclosure () throws -> [ModelContent]) async throws
    -> GenerateContentResponse {
    do {
      let evaluatedContent = try content()
      return try await GenerateContentResponse(internalResponse: internalModel
        .generateContent(evaluatedContent.toInternal()))
    } catch {
      throw GenerativeModel.generateContentError(from: error)
    }
  }

  /// Generates content from String and/or image inputs, given to the model as a prompt, that are
  /// representable as one or more ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for generating
  /// content from
  /// [zero-shot](https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting)
  /// or "direct" prompts. For
  /// [few-shot](https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting)
  /// prompts, see ``generateContent(_:)-58rm0``.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: A stream wrapping content generated by the model or a ``GenerateContentError``
  ///     error if an error occurred.
  @available(macOS 12.0, *)
  public func generateContentStream(_ parts: any ThrowingPartsRepresentable...)
    -> AsyncThrowingStream<GenerateContentResponse, Error> {
    return try generateContentStream([ModelContent(parts: parts)])
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: A stream wrapping content generated by the model or a ``GenerateContentError``
  ///     error if an error occurred.
  @available(macOS 12.0, *)
  public func generateContentStream(_ content: @autoclosure () throws -> [ModelContent])
    -> AsyncThrowingStream<GenerateContentResponse, Error> {
    let evaluatedContent: [ModelContent]
    do {
      evaluatedContent = try content()
    } catch let underlying {
      return AsyncThrowingStream { continuation in
        let error = GenerativeModel.generateContentError(from: underlying)
        continuation.finish(throwing: error)
      }
    }

    var responseIterator = internalModel
      .generateContentStream(evaluatedContent.toInternal()).makeAsyncIterator()
    return AsyncThrowingStream {
      do {
        return try await responseIterator.next()
          .flatMap { GenerateContentResponse(internalResponse: $0) }
      } catch {
        throw GenerativeModel.generateContentError(from: error)
      }
    }
  }

  /// Creates a new chat conversation using this model with the provided history.
  public func startChat(history: [ModelContent] = []) -> Chat {
    return Chat(model: self, history: history)
  }

  /// Runs the model's tokenizer on String and/or image inputs that are representable as one or more
  /// ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for tokenizing
  /// [zero-shot](https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting)
  /// or "direct" prompts. For
  /// [few-shot](https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting)
  /// input, see ``countTokens(_:)-9spwl``.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: The results of running the model's tokenizer on the input; contains
  /// ``CountTokensResponse/totalTokens``.
  /// - Throws: A ``CountTokensError`` if the tokenization request failed.
  public func countTokens(_ parts: any ThrowingPartsRepresentable...) async throws
    -> CountTokensResponse {
    return try await countTokens([ModelContent(parts: parts)])
  }

  /// Runs the model's tokenizer on the input content and returns the token count.
  ///
  /// - Parameter content: The input given to the model as a prompt.
  /// - Returns: The results of running the model's tokenizer on the input; contains
  /// ``CountTokensResponse/totalTokens``.
  /// - Throws: A ``CountTokensError`` if the tokenization request failed or the input content was
  /// invalid.
  public func countTokens(_ content: @autoclosure () throws -> [ModelContent]) async throws
    -> CountTokensResponse {
    do {
      let internalResponse = try await internalModel.countTokens(content().toInternal())
      return CountTokensResponse(internalResponse: internalResponse)
    } catch let error as InternalGenerativeAI.CountTokensError {
      switch error {
      case let .internalError(underlying: underlying):
        throw CountTokensError.internalError(underlying: underlying)
      }
    } catch {
      throw CountTokensError.internalError(underlying: error)
    }
  }

  /// Returns a model resource name of the form "models/model-name" based on `name`.
  private static func modelResourceName(name: String) -> String {
    if name.contains("/") {
      return name
    } else {
      return modelResourcePrefix + name
    }
  }

  /// Returns a `GenerateContentError` (for public consumption) from an internal error.
  ///
  /// If `error` is already a `GenerateContentError` the error is returned unchanged.
  private static func generateContentError(from error: Error) -> GenerateContentError {
    if let error = error as? GenerateContentError {
      return error
    } else if let error = error as? InternalGenerativeAI.GenerateContentError {
      switch error {
      case let .internalError(underlying: underlying):
        return GenerateContentError.internalError(underlying: underlying)
      case let .promptBlocked(response: response):
        return GenerateContentError
          .promptBlocked(response: GenerateContentResponse(internalResponse: response))
      case let .responseStoppedEarly(reason: reason, response: response):
        return GenerateContentError.responseStoppedEarly(
          reason: FinishReason(internalReason: reason),
          response: GenerateContentResponse(internalResponse: response)
        )
      }
    } else if let error = error as? InternalGenerativeAI.InvalidCandidateError {
      switch error {
      case let .emptyContent(underlyingError):
        return GenerateContentError
          .internalError(underlying: InvalidCandidateError
            .emptyContent(underlyingError: underlyingError))
      case let .malformedContent(underlyingError):
        return GenerateContentError
          .internalError(underlying: InvalidCandidateError
            .malformedContent(underlyingError: underlyingError))
      }
    } else if let error = error as? ImageConversionError {
      return GenerateContentError.promptImageContentError(underlying: error)
    } else if let error = error as? RPCError, error.isInvalidAPIKeyError() {
      return GenerateContentError.invalidAPIKey
    } else if let error = error as? RPCError, error.isUnsupportedUserLocationError() {
      return GenerateContentError.unsupportedUserLocation
    }
    return GenerateContentError.internalError(underlying: error)
  }
}

/// See ``GenerativeModel/countTokens(_:)-9spwl``.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public enum CountTokensError: Error {
  case internalError(underlying: Error)
}
