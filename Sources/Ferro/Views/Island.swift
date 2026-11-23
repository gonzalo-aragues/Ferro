import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView()
                .frame(width: model.outerSize.width, height: model.outerSize.height)
            Spacer(minLength: 0)
        }
        .frame(width: NotchModel.canvas.width, height: NotchModel.canvas.height)
        .environment(\.colorScheme, .dark)
    }
}

struct IslandView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        ZStack(alignment: .top) {
            FerroSurface(expanded: model.expanded, energy: energy, accent: media.accent, inset: model.topRadius)

            if model.expanded {
                ExpandedView()
                    .padding(.horizontal, model.topRadius)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).animation(.smooth(duration: 0.35).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.12))))
            } else {
                CollapsedView()
                    .padding(.horizontal, model.topRadius)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .clipShape(shape)
        .overlay {
            // Glass rim: invisible where it meets the bezel, catches light toward the bottom.
            shape.stroke(LinearGradient(colors: [.clear, .white.opacity(model.expanded ? 0.16 : 0.06)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .overlay {
            if model.dropTargeted {
                shape.stroke(media.accent.opacity(0.9), lineWidth: 1.5)
                    .shadow(color: media.accent, radius: 10)
                    .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(model.expanded ? 0.6 : 0), radius: 22, y: 12)
        .onDrop(of: [.fileURL, .image, .url, .plainText], isTargeted: $model.dropTargeted) { shelf.handleDrop($0) }
        .onChange(of: model.dropTargeted) { _, on in
            if on { withAnimation(.snappy) { model.tab = .shelf } }
        }
        .animation(.easeOut(duration: 0.2), value: model.dropTargeted)
    }

    private var energy: Double {
        if model.dropTargeted { return 1 }
        return media.isPlaying ? 0.75 : 0.22
    }
}

// MARK: - Collapsed pill (live activities)

struct CollapsedView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var timer: FocusTimer

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: model.wing)
            Spacer(minLength: 0)
            trailing.frame(width: model.wing)
        }
        .frame(height: model.notchSize.height)
        .opacity(model.activity == .none ? 0 : 1)
    }

    @ViewBuilder private var leading: some View {
        switch model.activity {
        case .music:
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 11, weight: .bold))
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 13, weight: .semibold))
        case .timerDone:
            Image(systemName: "bell.fill").foregroundStyle(.orange).symbolEffect(.wiggle)
        case .charging:
            Image(systemName: "bolt.fill").foregroundStyle(.green).symbolEffect(.bounce)
        case .copied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
        case .shelved:
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.white)
        case .none:
            Color.clear
        }
    }

    @ViewBuilder private var trailing: some View {
        let font = Font.system(size: 12, weight: .semibold).monospacedDigit()
        switch model.activity {
        case .music:
            EQBars(playing: media.isPlaying, color: media.accent)
        case .timer:
            Text(FocusTimer.format(timer.remaining)).font(font).foregroundStyle(.orange)
                .contentTransition(.numericText(countsDown: true))
        case .timerDone:
            Text("Done").font(font).foregroundStyle(.orange)
        case .charging(let lvl):
            Text("\(lvl)%").font(font).foregroundStyle(.green)
        case .copied:
            Text("Copied").font(.system(size: 11, weight: .semibold))
        case .shelved(let n):
            Text("+\(n)").font(font)
        case .none:
            Color.clear
        }
    }
}

// MARK: - Expanded island

struct ExpandedView: View {
    @EnvironmentObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            // Keep the menu-bar strip empty so nothing collides with app menus.
            Color.clear.frame(height: model.notchSize.height)
            HeaderRow()
                .frame(height: 32)
            Group {
                switch model.tab {
                case .music: MusicPanel()
                case .shelf: ShelfPanel()
                case .clipboard: ClipboardPanel()
                case .tools: ToolsPanel()
                }
            }
            .id(model.tab)
            .transition(.blurReplace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }
}

struct HeaderRow: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var battery: BatteryMonitor
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            // Tabs (left of the camera housing)
            HStack(spacing: 2) {
                ForEach(IslandTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.tab = tab }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.5))
                            .frame(width: 32, height: 22)
                            .background {
                                if model.tab == tab {
                                    Capsule().fill(.white.opacity(0.16))
                                        .matchedGeometryEffect(id: "tab", in: ns)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(3)
            .ferroGlass(Capsule(), tint: 0.5)

            Spacer(minLength: 16)

            // Status (right of the camera housing)
            HStack(spacing: 8) {
                TimelineView(.everyMinute) { tl in
                    Text(tl.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                if battery.hasBattery {
                    HStack(spacing: 3) {
                        Text("\(battery.level)%").font(.system(size: 11, weight: .medium).monospacedDigit())
                        Image(systemName: battery.symbol)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(battery.onAC ? .green : (battery.level <= 20 ? .red : .white), .white.opacity(0.5))
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}
