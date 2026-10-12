import SwiftUI

/// The updates themselves: a glass card with one row per item. It is the pending list before a run,
/// the live progress during one and the result afterwards.
struct QueueCard: View {
    @ObservedObject var model: RunModel
    @StateObject private var contentHeight = Box<CGFloat>(0)
    private let maxHeight: CGFloat = 252

    private var items: [QueueItem] {
        // Updates the app installs first, then problems, then macOS updates it only reports.
        let all = model.actionable + model.issues + model.manual
        // Once a run is over, anything that failed goes to the top, where it can't be missed.
        guard model.phase == .finished else { return all }
        return all.filter { $0.state == .failed } + all.filter { $0.state != .failed }
    }

    /// When the list scrolls, its bottom edge fades out instead of cutting a row in half.
    private var fade: some View {
        VStack(spacing: 0) {
            Color.black
            if contentHeight.value > maxHeight {
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        QueueRow(item: item)
                            .id(item.id)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 64).opacity(0.5)
                        }
                    }
                }
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight.value = $0 }
            }
            .scrollIndicators(.never)
            // Keep the update being installed in view.
            .onChange(of: model.currentItem?.id) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                guard let id = model.currentItem?.id else { return }
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: contentHeight.value) { _, _ in
                guard let id = model.currentItem?.id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(height: min(max(contentHeight.value, 60), maxHeight))
        .mask { fade }
        .glassCard(cornerRadius: 26)
        .frame(maxWidth: 560)
        .animation(.smooth, value: items.map(\.state.hashValue))
    }
}

struct QueueRow: View {
    let item: QueueItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            KindBadge(kind: item.kind, state: item.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !item.versions.isEmpty {
                    Text(item.versions)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if item.kind == .system {
                    Text("Install in System Settings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if item.state == .failed, let reason = item.reason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if item.bump != .update && item.state == .pending { BumpPill(bump: item.bump) }
            if item.state != .pending {
                StateMark(state: item.state, kind: item.kind)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(item.state == .running ? Palette.teal.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct KindBadge: View {
    let kind: Kind
    let state: ItemState

    private var tint: Color {
        switch kind {
        case .formula: return Palette.violet
        case .cask: return Palette.blue
        case .store: return Palette.teal
        case .system: return Palette.amber
        case .task: return Palette.red
        }
    }

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            .opacity(state == .skipped ? 0.5 : 1)
    }
}

private struct BumpPill: View {
    let bump: Bump

    private var tint: Color {
        switch bump {
        case .major: return Palette.red
        case .minor: return Palette.blue
        case .patch: return .secondary
        case .update: return .secondary
        }
    }

    var body: some View {
        Text(bump.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

private struct StateMark: View {
    let state: ItemState
    let kind: Kind

    var body: some View {
        Group {
            switch state {
            case .pending:
                Color.clear
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.mint)
            case .skipped:
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.teal)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.red)
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(duration: 0.4, bounce: 0.3), value: state)
    }
}
