//
//  PathBarView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct PathBarView: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .foregroundStyle(CatppuccinMochaTheme.mutedText)
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
