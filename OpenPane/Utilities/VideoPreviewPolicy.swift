//
//  VideoPreviewPolicy.swift
//  OpenPane
//

import Foundation
import UniformTypeIdentifiers

/// Keeps movie selections cheap: the embedded panel always uses a static
/// thumbnail, and large files skip AVFoundation format inspection entirely.
nonisolated enum VideoPreviewPolicy {
    static let maximumFormatInspectionByteCount: Int64 = 256 * 1_024 * 1_024

    static func isVideo(typeIdentifier: String?, fileExtension: String) -> Bool {
        let contentType = typeIdentifier.flatMap(UTType.init)
            ?? (fileExtension.isEmpty ? nil : UTType(filenameExtension: fileExtension))
        return contentType?.conforms(to: .movie) == true
    }

    static func shouldInspectFormat(
        typeIdentifier: String?,
        fileExtension: String,
        logicalSize: Int64?
    ) -> Bool {
        guard isVideo(typeIdentifier: typeIdentifier, fileExtension: fileExtension) else {
            return false
        }

        guard let logicalSize else {
            return false
        }
        return logicalSize <= maximumFormatInspectionByteCount
    }
}
