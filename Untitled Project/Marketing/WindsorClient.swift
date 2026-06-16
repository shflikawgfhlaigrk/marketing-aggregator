import Foundation

/// Talks to Windsor.ai's unified connector, which aggregates 325+ marketing
/// platforms behind a single REST endpoint. One API key, one call, every source.
///
/// Endpoint shape:
/// `https://connectors.windsor.ai/all?api_key=KEY&date_preset=last_7d&fields=source,clicks,spend`
struct WindsorClient {

    enum WindsorError: LocalizedError {
        case missingKey
        case badResponse(status: Int)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your Windsor.ai API key in Settings to load live data."
            case .badResponse(let status):
                return "Windsor.ai returned an error (HTTP \(status)). Check your key and try again."
            case .transport(let error):
                return "Couldn't reach Windsor.ai: \(error.localizedDescription)"
            }
        }
    }

    /// Fields requested from every connected source.
    static let defaultFields = ["source", "campaign", "clicks", "impressions", "spend", "conversions"]

    var session: URLSession = .shared

    /// Fetch unified rows across all of the user's connected marketing platforms.
    func fetch(
        apiKey: String,
        range: MarketingDateRange,
        fields: [String] = WindsorClient.defaultFields
    ) async throws -> [MetricRow] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw WindsorError.missingKey }

        var components = URLComponents(string: "https://connectors.windsor.ai/all")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "date_preset", value: range.rawValue),
            URLQueryItem(name: "fields", value: fields.joined(separator: ","))
        ]

        let request = URLRequest(url: components.url!)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WindsorError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WindsorError.badResponse(status: http.statusCode)
        }

        return try Self.decodeRows(from: data)
    }

    /// Windsor wraps rows in a top-level `data` array.
    private struct Envelope: Decodable { let data: [MetricRow] }

    static func decodeRows(from data: Data) throws -> [MetricRow] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope.data
        }
        // Some responses return a bare array; fall back to that.
        return (try? decoder.decode([MetricRow].self, from: data)) ?? []
    }
}
