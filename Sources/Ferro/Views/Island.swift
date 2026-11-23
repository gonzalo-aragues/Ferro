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
    @EnvironmentObject var claude: ClaudeWatcher

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        ZStack(alignment: .top) {
            FerroSurface(expanded: model.expanded, energy: energy, accent: accent, inset: model.topRadius,
                         solidTop: (model.notchSize.height + 4) / max(model.bodySize.height, 1))

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
        .background {
            // The open island is real Liquid Glass: the desktop refracts through it below the notch.
            IslandGlass(shape: shape).opacity(model.expanded ? 1 : 0)
        }
        .overlay {
            // Glass rim: invisible where it meets the bezel, catches light toward the bottom.
            shape.stroke(LinearGradient(colors: [.clear, .white.opacity(model.expanded ? 0.34 : 0.06)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .blendMode(.plusLighter)
        }
        .overlay {
            if model.expanded {
                // Inner specular sheen along the lower edge.
                shape
                    .stroke(LinearGradient(colors: [.clear, .clear, .white.opacity(0.14), accent.opacity(0.3)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 5)
                    .blur(radius: 2)
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
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
        if claude.isWorking { return 0.7 }
        return media.isPlaying ? 0.75 : 0.22
    }

    private var accent: Color {
        (model.tab == .claude && model.expanded) || (!media.isPlaying && claude.isWorking) ? ClaudeTheme.claude : media.accent
    }
}

// MARK: - Collapsed pill (live activities)

struct CollapsedView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var claude: ClaudeWatcher

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
        case .claude:
            ClaudeSpinner(size: 15)
        case .claudeDone:
            Text("✻").font(ClaudeTheme.mono(15, .bold)).foregroundStyle(ClaudeTheme.claude)
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
        case .claude:
            if let s = claude.sessions.first(where: { $0.working }) {
                if !s.steps.isEmpty {
                    Text("\(s.doneSteps)/\(s.steps.count)").font(ClaudeTheme.mono(12, .semibold))
                        .foregroundStyle(ClaudeTheme.claude)
                        .contentTransition(.numericText())
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        Text(ClaudeTheme.duration(s.elapsed(at: tl.date))).font(ClaudeTheme.mono(11, .semibold))
                            .foregroundStyle(ClaudeTheme.claude)
                    }
                }
            }
        case .claudeDone:
            Text("Done").font(ClaudeTheme.mono(12, .semibold)).foregroundStyle(ClaudeTheme.claude)
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
                case .claude: ClaudePanel()
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
    @ViewBuilder private func icon(_ tab: IslandTab) -> some View {
        let on = model.tab == tab
        if tab == .claude {
            // Claude's starburst; spins and glows orange while Claude is working.
            ClaudeSpinner(animating: claude.isWorking, size: 14,
                          color: claude.isWorking ? ClaudeTheme.claude : .white.opacity(on ? 1 : 0.5))
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? .white : .white.opacity(0.5))
        }
    }

    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var battery: BatteryMonitor
    @EnvironmentObject var claude: ClaudeWatcher
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            // Tabs (left of the camera housing)
            HStack(spacing: 2) {
                ForEach(IslandTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.tab = tab }
                    } label: {
                        icon(tab)
                            .frame(width: 32, height: 22)
                            .background {
                                if model.tab == tab {
                                    Capsule().fill(.white.opacity(0.14))
                                        .overlay(Capsule().strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
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
            .ferroGlass(Capsule(), tint: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}
