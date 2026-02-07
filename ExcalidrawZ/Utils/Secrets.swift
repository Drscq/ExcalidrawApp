//
//  Secrets.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/14/25.
//

import Foundation

struct Secrets {
    static let shared = Secrets()

    let collabURL: URL
    let nvidiaAPIKey: String
    let nvidiaBaseURL: URL
    let nvidiaModel: String

    private init() {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            fatalError("Unable to load Secrets.plist.")
        }

        guard let collabURLString = dict["COLLAB_URL"] as? String,
              let collabURL = URL(string: collabURLString) else {
            fatalError("Secrets.plist is missing a valid COLLAB_URL.")
        }
        self.collabURL = collabURL

        self.nvidiaAPIKey = (dict["NVIDIA_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let defaultBaseURLString = "https://integrate.api.nvidia.com/v1"
        let baseURLString = (dict["NVIDIA_BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nvidiaBaseURL = URL(string: (baseURLString?.isEmpty == false ? baseURLString! : defaultBaseURLString))!

        let defaultModel = "moonshotai/kimi-k2.5"
        let model = (dict["NVIDIA_MODEL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nvidiaModel = (model?.isEmpty == false ? model! : defaultModel)
    }
}
