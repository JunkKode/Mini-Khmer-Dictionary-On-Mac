//
//  CopyToastView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Brief confirmation that floats over the list after a copy.
struct CopyToastView: View {
    let notice: CopyNotice

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(notice.includesDefinition ? "Copied entry" : "Copied")
                .foregroundStyle(.secondary)
            Text(notice.word)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityHidden(true)  // the copy itself posts a VoiceOver announcement
    }
}
