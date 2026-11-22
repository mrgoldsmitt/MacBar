//
//  AboutSettingsPane.swift
//  MacBar
//

import SwiftUI

struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var upstreamURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            contentForm(cornerStyle: .continuous)
        } else {
            contentForm(cornerStyle: .circular)
        }
    }

    @ViewBuilder
    private func contentForm(cornerStyle: RoundedCornerStyle) -> some View {
        IceForm(spacing: 0) {
            mainContent(containerShape: RoundedRectangle(cornerRadius: 20, style: cornerStyle))
            Spacer(minLength: 10)
            bottomBar(containerShape: Capsule(style: cornerStyle))
        }
    }

    @ViewBuilder
    private func mainContent(containerShape: some InsettableShape) -> some View {
        IceSection(spacing: 0, options: .plain) {
            appIconAndCopyrightSection
                .layoutPriority(1)
        }
        .padding(.top, 5)
        .padding([.horizontal, .bottom], 30)
        .frame(maxHeight: 500)
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 16) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 210)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MacBar")
                        .font(.system(size: 72))
                        .foregroundStyle(.primary)

                    Text("Version \(Constants.versionString) (\(Constants.buildString))")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text("Native macOS menu bar manager with macOS 27 support")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Based on Ice by Jordan Baird · GPL-3.0 License")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary.opacity(0.75))

                    Text(Constants.copyrightString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.67))
                }
                .fontWeight(.medium)
            }
        }
    }

    @ViewBuilder
    private func bottomBar(containerShape: some InsettableShape) -> some View {
        HStack {
            Button("Quit MacBar") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Button("Upstream Ice") {
                openURL(upstreamURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        ContainerRelativeShape()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
