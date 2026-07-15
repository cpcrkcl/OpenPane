//
//  PathBarView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct PathBarView: View {
    let path: String
    var onNavigate: ((URL) -> Void)? = nil

    private var segments: [(name: String, url: URL)] {
        guard path != "Network", !path.isEmpty else {
            return []
        }

        var segments: [(name: String, url: URL)] = []
        let components = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .pathComponents
        var currentURL = URL(fileURLWithPath: "/", isDirectory: true)

        for component in components {
            if component == "/" {
                currentURL = URL(fileURLWithPath: "/", isDirectory: true)
                segments.append((name: "/", url: currentURL))
                continue
            }

            currentURL.appendPathComponent(component, isDirectory: true)
            segments.append((name: component, url: currentURL))
        }

        return segments
    }

    var body: some View {
        Group {
            if let onNavigate, !segments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
                            }

                            Button {
                                onNavigate(segment.url)
                            } label: {
                                Text(segment.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(
            CatppuccinMochaTheme.mantle.opacity(0.78),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(CatppuccinMochaTheme.surface1.opacity(0.7), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }
}
