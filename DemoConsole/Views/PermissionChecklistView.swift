//
//  PermissionChecklistView.swift
//  DemoConsole
//
//  Created by Sun on 2025/12/22.
//
//  权限检查列表视图
//  引导用户完成屏幕录制权限和工具链配置
//

import SwiftUI

struct PermissionChecklistView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var showScrcpyInstall = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("设备演示检查清单")
                    .font(.title)
                    .fontWeight(.bold)

                Text("在开始使用前，请确保以下项目已准备就绪")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 32)

            Divider()

            // 检查项列表
            ScrollView {
                VStack(spacing: 16) {
                    // 权限检查
                    SectionHeader(title: "系统权限", icon: "lock.shield")

                    ForEach(appState.permissionChecker.permissions) { permission in
                        PermissionCheckRow(
                            permission: permission,
                            action: {
                                appState.permissionChecker.openSystemPreferences(for: permission.id)
                            },
                            onRequestPermission: {
                                // 根据权限类型请求相应权限
                                switch permission.id {
                                case "camera":
                                    Task {
                                        _ = await appState.permissionChecker.requestCameraPermission()
                                    }
                                case "screenRecording":
                                    Task {
                                        _ = await appState.permissionChecker.requestScreenRecordingPermission()
                                    }
                                default:
                                    break
                                }
                            }
                        )
                    }

                    // 工具链检查
                    SectionHeader(title: "工具链", icon: "wrench.and.screwdriver")

                    let toolchainItems = appState.permissionChecker.checkToolchain(manager: appState.toolchainManager)
                    ForEach(toolchainItems) { item in
                        ToolchainCheckRow(item: item) {
                            if item.name == "scrcpy" {
                                showScrcpyInstall = true
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack {
                Button("重新检查") {
                    Task {
                        await appState.permissionChecker.checkAll()
                        await appState.toolchainManager.refresh()
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("开始使用") {
                    appState.markSetupComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReadyToContinue)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 20)
        .sheet(isPresented: $showScrcpyInstall) {
            ScrcpyInstallView()
                .environmentObject(appState)
        }
        .onAppear {
            // 视图出现时立即检查一次权限
            Task {
                await appState.permissionChecker.checkAll()
            }
        }
    }

    var isReadyToContinue: Bool {
        // 需要摄像头权限、屏幕录制权限和工具链就绪
        appState.permissionChecker.cameraStatus == .granted &&
            appState.permissionChecker.screenRecordingStatus == .granted &&
            appState.toolchainManager.isReady
    }
}

// MARK: - 分区标题

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - 权限检查行

struct PermissionCheckRow: View {
    let permission: PermissionItem
    let action: () -> Void
    /// 屏幕录制权限需要先请求才能在系统设置中显示
    var onRequestPermission: (() -> Void)?

    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: permission.status.icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(permission.name)
                            .font(.body)
                            .fontWeight(.medium)

                        if permission.isRequired {
                            Text("必需")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }

                    Text(permission.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if permission.status != .granted {
                    Button("帮助") {
                        showingHelp.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)

                    Button("授权") {
                        // 对于屏幕录制，先请求权限触发系统添加到列表
                        if let onRequest = onRequestPermission {
                            onRequest()
                        }
                        // 延迟一点再打开系统设置，让用户看到提示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            action()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // 帮助说明
            if showingHelp, permission.status != .granted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("如果在系统设置中找不到 DemoConsole：")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("1. 点击列表下方的「+」按钮")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("2. 在应用程序中找到 DemoConsole")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("3. 选中后点击「打开」")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if permission.id == "screenRecording" {
                        Text("💡 提示：开发期间运行的应用可能需要手动添加")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    var iconColor: Color {
        switch permission.status {
        case .granted:
            .green
        case .denied:
            .red
        default:
            .orange
        }
    }
}

// MARK: - 工具链检查行

struct ToolchainCheckRow: View {
    let item: ToolchainCheckItem
    var onInstall: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.statusIcon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if item.isRequired {
                        Text("必需")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }

                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if case .notInstalled = item.status, let onInstall {
                Button("安装") {
                    onInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    var iconColor: Color {
        switch item.status {
        case .installed:
            .green
        case .installing:
            .blue
        case .notInstalled:
            .orange
        case .error:
            .red
        }
    }

    var statusText: String {
        switch item.status {
        case let .installed(version):
            version
        case .installing:
            "检查中..."
        case .notInstalled:
            "未安装"
        case let .error(message):
            message
        }
    }
}

// MARK: - Scrcpy 安装视图

struct ScrcpyInstallView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("安装 scrcpy")
                    .font(.title2.bold())

                Text("scrcpy 是用于投屏 Android 设备的工具")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // 安装说明
            VStack(alignment: .leading, spacing: 12) {
                Text("请使用 Homebrew 安装：")
                    .font(.headline)

                HStack {
                    Text("brew install scrcpy")
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install scrcpy", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Text("如果没有安装 Homebrew，请先访问 brew.sh 安装")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // 按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("完成") {
                    Task {
                        await appState.toolchainManager.refresh()
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        PermissionChecklistView()
            .environmentObject(AppState())
    }
    .frame(width: 800, height: 700)
}
