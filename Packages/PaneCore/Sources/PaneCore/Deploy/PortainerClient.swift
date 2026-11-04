import Foundation

/// Why a Portainer request failed. Never carries the token.
enum PortainerError: Error, Hashable, Sendable {
    case unauthorized
    case forbidden
    /// 404: on the container list this means no environment with that id.
    case notFound
    case status(Int)
    case malformed(String)
}

/// What image inspect adds for a container without a revision label.
struct PortainerImage: Hashable, Sendable {
    let created: Date?
    let labels: [String: String]
}

/// The Docker calls the deploy check needs, through Portainer's proxy for one environment.
struct PortainerClient: Sendable {
    let http: any HTTPClient
    let server: PortainerServer
    let token: String

    func version() async throws -> String {
        let data = try await get(["api", "system", "status"])
        return try Self.parseVersion(data)
    }

    /// Running containers.
    func containers() async throws -> [PortainerContainer] {
        let data = try await get(["api", "endpoints", String(server.environmentID), "docker", "containers", "json"])
        return try Self.parseContainers(data)
    }

    func image(id: String) async throws -> PortainerImage {
        guard Self.isImageID(id) else { throw PortainerError.malformed("image id") }
        let data = try await get(["api", "endpoints", String(server.environmentID), "docker", "images", id, "json"])
        return try Self.parseImage(data)
    }

    private func get(_ segments: [String]) async throws -> Data {
        var url = server.baseURL
        for segment in segments { url.append(path: segment) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(token, forHTTPHeaderField: "X-API-Key")
        request.setValue("Pane", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw PortainerError.unauthorized
        case 403: throw PortainerError.forbidden
        case 404: throw PortainerError.notFound
        default: throw PortainerError.status(response.statusCode)
        }
    }

    static func isImageID(_ id: String) -> Bool {
        let hex = id.hasPrefix("sha256:") ? id.dropFirst("sha256:".count) : Substring(id)
        return (12...64).contains(hex.count) && hex.allSatisfy(\.isHexDigit)
    }

    private struct StatusReply: Decodable {
        let version: String

        enum CodingKeys: String, CodingKey {
            case version = "Version"
        }
    }

    static func parseVersion(_ data: Data) throws -> String {
        guard let reply = try? JSONDecoder().decode(StatusReply.self, from: data) else { throw PortainerError.malformed("status") }
        return reply.version
    }

    private struct ContainerReply: Decodable {
        let id: String
        let names: [String]?
        let image: String?
        let imageID: String?
        let state: String?
        let created: Double?
        let labels: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case names = "Names"
            case image = "Image"
            case imageID = "ImageID"
            case state = "State"
            case created = "Created"
            case labels = "Labels"
        }
    }

    static func parseContainers(_ data: Data) throws -> [PortainerContainer] {
        guard let replies = try? JSONDecoder().decode([ContainerReply].self, from: data) else {
            throw PortainerError.malformed("containers")
        }
        return replies.map { reply in
            let name = reply.names?.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(reply.id.prefix(12))
            return PortainerContainer(
                id: reply.id,
                name: name,
                image: reply.image ?? "",
                imageID: reply.imageID ?? "",
                state: reply.state ?? "",
                created: Date(timeIntervalSince1970: reply.created ?? 0),
                labels: reply.labels ?? [:]
            )
        }
    }

    private struct ImageReply: Decodable {
        struct Config: Decodable {
            let labels: [String: String]?

            enum CodingKeys: String, CodingKey {
                case labels = "Labels"
            }
        }

        let created: String?
        let config: Config?

        enum CodingKeys: String, CodingKey {
            case created = "Created"
            case config = "Config"
        }
    }

    static func parseImage(_ data: Data) throws -> PortainerImage {
        guard let reply = try? JSONDecoder().decode(ImageReply.self, from: data) else { throw PortainerError.malformed("image") }
        return PortainerImage(created: reply.created.flatMap(CodeDate.parse), labels: reply.config?.labels ?? [:])
    }
}
