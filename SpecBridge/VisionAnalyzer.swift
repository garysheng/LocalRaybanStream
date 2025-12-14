//
//  VisionAnalyzer.swift
//  SpecBridge
//
//  Analyzes frames using OpenRouter vision API to detect shoe violations.
//

import Foundation
import UIKit
import Combine

struct VisionAnalysisResult {
    let hasLegsOrFeet: Bool
    let hasShoes: Bool
    let hasHands: Bool
    let hasGloves: Bool
    let isViolation: Bool
    let violationType: ViolationType
    let rawResponse: String
    
    enum ViolationType {
        case none
        case noShoes
        case noGloves
        case both
    }
}

@MainActor
class VisionAnalyzer: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastResult: VisionAnalysisResult?
    @Published var lastError: String?
    
    // OpenRouter API configuration
    // Using Gemini 2.5 Flash for speed - one of the fastest vision models
    private let apiEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    private let model = "google/gemini-2.5-flash"
    
    // API key loaded from Secrets.swift (gitignored)
    private var apiKey: String {
        Secrets.openRouterAPIKey
    }
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func analyzeFrame(_ image: UIImage) async -> VisionAnalysisResult? {
        guard !apiKey.isEmpty, apiKey != "your-openrouter-api-key-here" else {
            lastError = "OpenRouter API key not configured in Secrets.swift"
            print("VisionAnalyzer: API key not configured")
            return nil
        }
        
        print("VisionAnalyzer: Starting analysis...")
        isAnalyzing = true
        lastError = nil
        
        defer {
            isAnalyzing = false
        }
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            lastError = "Failed to encode image"
            return nil
        }
        let base64Image = imageData.base64EncodedString()
        
        // Build the request
        let prompt = """
        This is a FIRST-PERSON view from smart glasses worn by a worker. You are checking if THE WEARER has proper PPE.
        
        IMPORTANT: Only check the WEARER'S OWN body parts, NOT other people in the scene.
        - The wearer's hands appear CLOSE to the camera, typically at the BOTTOM or SIDES of the frame, and are LARGE
        - The wearer's feet appear at the VERY BOTTOM of the frame when looking down, very close and large
        - Other people in the scene appear SMALLER, in the MIDDLE or DISTANCE of the frame - IGNORE THEM
        
        Check ONLY for the wearer's own hands and feet:
        1. Are the WEARER'S legs/feet visible? (very close, bottom of frame, looking down at own feet)
        2. If wearer's feet visible, are they wearing shoes?
        3. Are the WEARER'S hands visible? (close to camera, large, at edges/bottom of frame)
        4. If wearer's hands visible, are they wearing gloves?
        
        Respond ONLY in this exact JSON format:
        {"has_legs_or_feet": true/false, "has_shoes": true/false, "has_hands": true/false, "has_gloves": true/false}
        
        Rules:
        - ONLY flag the wearer's OWN hands/feet (close, large, at frame edges)
        - IGNORE other people visible in the scene (they appear smaller, in the middle distance)
        - has_shoes = true only if wearer's visible feet have shoes
        - has_gloves = true only if wearer's visible hands have gloves
        - If wearer's body parts aren't visible, set those to false
        """
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 200,
            "temperature": 0.1
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            lastError = "Failed to serialize request"
            return nil
        }
        
        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("SpecBridge-ShoeDetection", forHTTPHeaderField: "X-Title")
        request.httpBody = jsonData
        
        do {
            print("VisionAnalyzer: Sending request to OpenRouter...")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                print("VisionAnalyzer: Invalid response")
                return nil
            }
            
            print("VisionAnalyzer: Got response with status \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let errorText = String(data: data, encoding: .utf8) {
                    lastError = "API error \(httpResponse.statusCode): \(errorText)"
                    print("VisionAnalyzer: API error - \(errorText)")
                } else {
                    lastError = "API error \(httpResponse.statusCode)"
                }
                return nil
            }
            
            // Parse OpenRouter response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                lastError = "Failed to parse API response"
                print("VisionAnalyzer: Failed to parse response")
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("VisionAnalyzer: Raw response - \(rawResponse)")
                }
                return nil
            }
            
            // Parse the model's JSON response
            print("VisionAnalyzer: Model response - \(content)")
            let result = parseAnalysisResponse(content)
            print("VisionAnalyzer: Result - violation=\(result.isViolation), type=\(result.violationType)")
            lastResult = result
            return result
            
        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            print("VisionAnalyzer: Network error - \(error)")
            return nil
        }
    }
    
    private func parseAnalysisResponse(_ content: String) -> VisionAnalysisResult {
        // Try to extract JSON from the response
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle markdown code blocks
        if jsonString.contains("```") {
            if let jsonMatch = jsonString.range(of: "\\{[^}]+\\}", options: .regularExpression) {
                jsonString = String(jsonString[jsonMatch])
            }
        }
        
        // Try to parse as JSON
        if let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            
            let hasLegsOrFeet = parsed["has_legs_or_feet"] as? Bool ?? false
            let hasShoes = parsed["has_shoes"] as? Bool ?? false
            let hasHands = parsed["has_hands"] as? Bool ?? false
            let hasGloves = parsed["has_gloves"] as? Bool ?? false
            
            // Determine violation type
            let shoeViolation = hasLegsOrFeet && !hasShoes
            let gloveViolation = hasHands && !hasGloves
            
            let violationType: VisionAnalysisResult.ViolationType
            if shoeViolation && gloveViolation {
                violationType = .both
            } else if shoeViolation {
                violationType = .noShoes
            } else if gloveViolation {
                violationType = .noGloves
            } else {
                violationType = .none
            }
            
            return VisionAnalysisResult(
                hasLegsOrFeet: hasLegsOrFeet,
                hasShoes: hasShoes,
                hasHands: hasHands,
                hasGloves: hasGloves,
                isViolation: shoeViolation || gloveViolation,
                violationType: violationType,
                rawResponse: content
            )
        }
        
        // Fallback: try to interpret the response manually
        let lowercased = content.lowercased()
        let hasLegsOrFeet = lowercased.contains("has_legs_or_feet") && lowercased.contains("true")
        let hasShoes = lowercased.contains("has_shoes") && lowercased.contains("true")
        let hasHands = lowercased.contains("has_hands") && lowercased.contains("true")
        let hasGloves = lowercased.contains("has_gloves") && lowercased.contains("true")
        
        let shoeViolation = hasLegsOrFeet && !hasShoes
        let gloveViolation = hasHands && !hasGloves
        
        let violationType: VisionAnalysisResult.ViolationType
        if shoeViolation && gloveViolation {
            violationType = .both
        } else if shoeViolation {
            violationType = .noShoes
        } else if gloveViolation {
            violationType = .noGloves
        } else {
            violationType = .none
        }
        
        return VisionAnalysisResult(
            hasLegsOrFeet: hasLegsOrFeet,
            hasShoes: hasShoes,
            hasHands: hasHands,
            hasGloves: hasGloves,
            isViolation: shoeViolation || gloveViolation,
            violationType: violationType,
            rawResponse: content
        )
    }
}

