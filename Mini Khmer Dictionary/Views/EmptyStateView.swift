//
//  EmptyStateView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Stands in for `ContentUnavailableView`, which needs macOS 14.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
