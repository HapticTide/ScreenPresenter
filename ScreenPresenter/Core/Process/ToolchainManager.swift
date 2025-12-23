//
//  ToolchainManager.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/22.
//
//  工具链管理器
//  管理内置的 adb、scrcpy 工具
//  优先使用 Bundle 内置版本，回退到系统安装版本
//

import AppKit
import Foundation

// MARK: - 工具链状态

enum ToolchainStatus: Equatable {
    case notInstalled
    case installing
    case installed(version: String)
    case error(String)

    var isReady: Bool {
        if case .installed = self { return true }
        return false
    }
}

// MARK: - 工具链管理器

@MainActor
final class ToolchainManager {
    // MARK: - 常量

    /// Bundle 内置工具目录名
    private static let toolsDirectoryName = "Tools"

    // MARK: - 状态

    private(set) var adbStatus: ToolchainStatus = .notInstalled
    private(set) var scrcpyStatus: ToolchainStatus = .notInstalled

    /// 是否全部就绪
    var isReady: Bool {
        adbStatus.isReady && scrcpyStatus.isReady
    }

    /// 是否正在安装 scrcpy
    private(set) var isInstallingScrcpy = false

    /// 安装日志
    private(set) var installLog: String = ""

    // MARK: - 路径

    /// 内嵌的 adb 路径（在 App Bundle 中）
    var bundledAdbPath: String? {
        // 尝试多种路径
        if
            let path = Bundle.main.path(
                forResource: "adb",
                ofType: nil,
                inDirectory: "\(Self.toolsDirectoryName)/platform-tools"
            ) {
            return path
        }
        if let path = Bundle.main.path(forResource: "adb", ofType: nil, inDirectory: Self.toolsDirectoryName) {
            return path
        }
        return Bundle.main.path(forResource: "adb", ofType: nil, inDirectory: "tools")
    }

    /// 内嵌的 scrcpy 路径
    var bundledScrcpyPath: String? {
        if let path = Bundle.main.path(forResource: "scrcpy", ofType: nil, inDirectory: Self.toolsDirectoryName) {
            return path
        }
        return Bundle.main.path(forResource: "scrcpy", ofType: nil, inDirectory: "tools")
    }

    /// 系统安装的 adb 路径
    private var systemAdbPath: String?

    /// 系统安装的 scrcpy 路径
    private var systemScrcpyPath: String?

    /// adb 路径（优先使用内嵌版本）
    var adbPath: String {
        if let bundled = bundledAdbPath, FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return systemAdbPath ?? "/usr/local/bin/adb"
    }

    /// scrcpy 路径（优先使用内嵌版本）
    var scrcpyPath: String {
        if let bundled = bundledScrcpyPath, FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return systemScrcpyPath ?? "/opt/homebrew/bin/scrcpy"
    }

    // MARK: - 私有属性

    private let processRunner = ProcessRunner()

    // MARK: - 公开方法

    /// 设置工具链
    func setup() async {
        AppLogger.app.info("开始设置工具链")

        // 检查 adb
        await setupAdb()

        // 检查 scrcpy
        await checkScrcpy()

        AppLogger.app.info("工具链设置完成 - adb: \(adbVersionDescription), scrcpy: \(scrcpyVersionDescription)")
    }

    /// 重新检查工具链
    func refresh() async {
        await setupAdb()
        await checkScrcpy()
    }

    // MARK: - adb 设置

    private func setupAdb() async {
        adbStatus = .installing

        // 1. 首先检查内嵌的 adb
        if let bundledPath = bundledAdbPath, FileManager.default.fileExists(atPath: bundledPath) {
            // 确保可执行权限
            await ensureExecutable(bundledPath)

            if let version = await getToolVersion(bundledPath, versionArgs: ["version"]) {
                adbStatus = .installed(version: "内嵌 v\(version)")
                AppLogger.app.info("使用内嵌 adb: \(bundledPath)")
                return
            }
        }

        // 2. 查找系统安装的 adb
        if let systemPath = await findSystemTool("adb") {
            systemAdbPath = systemPath
            if let version = await getToolVersion(systemPath, versionArgs: ["version"]) {
                adbStatus = .installed(version: version)
                AppLogger.app.info("使用系统 adb: \(systemPath)")
                return
            }
        }

        // 3. 未找到 adb
        adbStatus = .error("未找到 adb")
        AppLogger.app.warning("未找到 adb")
    }

    // MARK: - scrcpy 设置

    private func checkScrcpy() async {
        scrcpyStatus = .installing

        // 1. 首先检查内嵌的 scrcpy
        if let bundledPath = bundledScrcpyPath, FileManager.default.fileExists(atPath: bundledPath) {
            // 确保可执行权限
            await ensureExecutable(bundledPath)

            if let version = await getToolVersion(bundledPath, versionArgs: ["--version"]) {
                scrcpyStatus = .installed(version: "内嵌 v\(version)")
                AppLogger.app.info("使用内嵌 scrcpy: \(bundledPath)")
                return
            }
        }

        // 2. 查找系统安装的 scrcpy
        if let systemPath = await findSystemTool("scrcpy") {
            systemScrcpyPath = systemPath
            if let version = await getToolVersion(systemPath, versionArgs: ["--version"]) {
                scrcpyStatus = .installed(version: version)
                AppLogger.app.info("使用系统 scrcpy: \(systemPath)")
                return
            }
        }

        // 3. 未安装
        scrcpyStatus = .notInstalled
        AppLogger.app.warning("未找到 scrcpy")
    }

    /// 检查 Homebrew 是否已安装
    func checkHomebrew() async -> Bool {
        await findBrewPath() != nil
    }

    /// 查找 Homebrew 路径
    private func findBrewPath() async -> String? {
        let brewPaths = [
            "/opt/homebrew/bin/brew", // Apple Silicon
            "/usr/local/bin/brew", // Intel Mac
        ]

        for path in brewPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// 一键安装 scrcpy（通过 Homebrew）
    func installScrcpy() async {
        guard !isInstallingScrcpy else { return }

        isInstallingScrcpy = true
        installLog = "🔍 正在检查 Homebrew...\n"
        scrcpyStatus = .installing

        guard let brewPath = await findBrewPath() else {
            installLog += "❌ 未检测到 Homebrew\n\n"
            installLog += "请先安装 Homebrew:\n/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            scrcpyStatus = .error("请先安装 Homebrew")
            isInstallingScrcpy = false
            return
        }

        installLog += "✅ 找到 Homebrew: \(brewPath)\n\n"
        installLog += "🍺 正在通过 Homebrew 安装 scrcpy...\n\n"

        do {
            _ = try await processRunner.startBackground(
                brewPath,
                arguments: ["install", "scrcpy"],
                onOutput: { [weak self] output in
                    Task { @MainActor in
                        self?.installLog += output
                    }
                },
                onTermination: { [weak self] exitCode in
                    Task { @MainActor in
                        if exitCode == 0 {
                            self?.installLog += "\n\n✅ scrcpy 安装成功！"
                            await self?.refresh()
                        } else {
                            self?.installLog += "\n\n❌ 安装失败 (退出码: \(exitCode))"
                            self?.scrcpyStatus = .error("安装失败")
                        }
                        self?.isInstallingScrcpy = false
                    }
                }
            )
        } catch {
            installLog += "\n\n❌ 错误: \(error.localizedDescription)"
            scrcpyStatus = .error(error.localizedDescription)
            isInstallingScrcpy = false
        }
    }

    /// 打开终端手动安装
    func openTerminalForInstall() {
        let command = "brew install scrcpy"

        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - 辅助方法

    /// 在系统路径中查找工具
    private func findSystemTool(_ name: String) async -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/\(name)", // Homebrew (Apple Silicon)
            "/usr/local/bin/\(name)", // Homebrew (Intel)
            "/usr/bin/\(name)", // System
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/\(name)", // Android SDK
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 使用 which 命令查找
        do {
            let result = try await processRunner.shell("/bin/zsh -l -c 'which \(name)'")
            if result.isSuccess {
                let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty, !path.contains("not found"), FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            // 忽略
        }

        return nil
    }

    /// 确保文件可执行
    private func ensureExecutable(_ path: String) async {
        do {
            _ = try await processRunner.shell("chmod +x '\(path)'")
        } catch {
            // 忽略
        }
    }

    /// 获取工具版本
    private func getToolVersion(_ path: String, versionArgs: [String]) async -> String? {
        do {
            let result = try await processRunner.run(path, arguments: versionArgs)
            let output = result.stdout + result.stderr

            // 提取版本号
            if let match = output.firstMatch(of: /(\d+\.\d+(\.\d+)?)/) {
                return String(match.1)
            }

            // 如果没有匹配到版本号但命令成功，返回 unknown
            if result.isSuccess {
                return "unknown"
            }
        } catch {
            // 忽略
        }
        return nil
    }
}

// MARK: - 便捷扩展

extension ToolchainManager {
    /// 获取 adb 版本描述
    var adbVersionDescription: String {
        switch adbStatus {
        case .notInstalled:
            "未安装"
        case .installing:
            "检查中..."
        case let .installed(version):
            version
        case let .error(message):
            message
        }
    }

    /// 获取 scrcpy 版本描述
    var scrcpyVersionDescription: String {
        switch scrcpyStatus {
        case .notInstalled:
            "未安装 - 点击安装"
        case .installing:
            "安装中..."
        case let .installed(version):
            "v\(version)"
        case let .error(message):
            message
        }
    }

    /// scrcpy 是否需要安装
    var needsScrcpyInstall: Bool {
        if case .notInstalled = scrcpyStatus { return true }
        if case .error = scrcpyStatus { return true }
        return false
    }
}
