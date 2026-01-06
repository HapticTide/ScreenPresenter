//
//  UpdateManager.swift
//  ScreenPresenter
//
//  Created by Sun on 2026/1/6.
//
//  自动更新管理器
//  基于 Sparkle 框架，支持 GitHub 私有仓库分发
//

import Foundation
import Sparkle

// MARK: - 更新管理器

/// 自动更新管理器
/// 封装 Sparkle 更新逻辑，支持私有仓库 Token 认证
final class UpdateManager: NSObject {

    // MARK: - Singleton

    static let shared = UpdateManager()

    // MARK: - Properties

    /// Sparkle 更新控制器
    private var updaterController: SPUStandardUpdaterController?

    /// 是否已初始化
    private(set) var isInitialized = false

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// 初始化更新管理器
    /// 应在应用启动时调用
    func initialize() {
        guard !isInitialized else { return }

        // 创建 Sparkle 更新控制器
        // startingUpdater: true 表示立即启动后台更新检查
        // updaterDelegate: self 用于自定义行为（如私有仓库认证）
        // userDriverDelegate: nil 使用默认 UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        isInitialized = true
        AppLogger.app.info("✅ UpdateManager 已初始化")
    }

    // MARK: - Public API

    /// 检查更新（用户手动触发）
    @objc func checkForUpdates() {
        guard let controller = updaterController else {
            AppLogger.app.warning("⚠️ UpdateManager 未初始化，无法检查更新")
            return
        }

        AppLogger.app.info("🔄 用户手动检查更新...")
        controller.checkForUpdates(nil)
    }

    /// 是否可以检查更新
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    /// 获取上次更新检查时间
    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }

    /// 自动检查更新是否启用
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? true }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 自动下载更新是否启用
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController?.updater.automaticallyDownloadsUpdates ?? false }
        set { updaterController?.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// 更新检查间隔（秒）
    var updateCheckInterval: TimeInterval {
        get { updaterController?.updater.updateCheckInterval ?? 86400 }
        set { updaterController?.updater.updateCheckInterval = newValue }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {

    /// 自定义 appcast 请求（用于私有仓库访问 appcast.xml）
    func updater(
        _ updater: SPUUpdater,
        willSendFeedRequest request: NSMutableURLRequest
    ) {
        // 如果配置了 GitHub Token，添加认证头以访问私有仓库
        if let token = githubAccessToken, !token.isEmpty {
            // 对于 raw.githubusercontent.com，需要使用 Bearer token
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            AppLogger.app.debug("🔐 已为 appcast 请求添加 GitHub Token 认证")
        }
    }

    /// 自定义下载请求（用于私有仓库 Token 认证下载 Release Assets）
    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        // 如果配置了 GitHub Token，添加认证头
        if let token = githubAccessToken, !token.isEmpty {
            // GitHub Release Assets 需要 Accept 头指定媒体类型
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            AppLogger.app.debug("🔐 已为更新下载添加 GitHub Token 认证")
        }
    }

    /// 允许的 channels（可用于区分 stable/beta）
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // 默认只接收稳定版
        // 如果需要 beta 通道，可以返回 ["beta"]
        return []
    }

    /// 自定义 appcast URL（可动态修改）
    func feedURLString(for updater: SPUUpdater) -> String? {
        // 返回 nil 使用 Info.plist 中的 SUFeedURL
        // 也可以在这里动态返回不同的 URL
        return nil
    }

    // MARK: - Private Helpers

    /// 从配置或环境变量获取 GitHub Access Token
    private var githubAccessToken: String? {
        // 优先级：
        // 1. UserDefaults 存储的 token
        // 2. Secrets.swift 中的硬编码 token（本地配置）
        // 3. 环境变量

        if let token = UserDefaults.standard.string(forKey: "GitHubAccessToken"), !token.isEmpty {
            return token
        }

        // 使用 Secrets.swift 中的 token（不会提交到 Git）
        if !Secrets.githubToken.isEmpty {
            return Secrets.githubToken
        }

        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            return token
        }

        return nil
    }
}

// MARK: - Token 配置

extension UpdateManager {

    /// 设置 GitHub Access Token（用于私有仓库）
    /// - Parameter token: Personal Access Token
    func setGitHubToken(_ token: String?) {
        if let token = token, !token.isEmpty {
            UserDefaults.standard.set(token, forKey: "GitHubAccessToken")
            AppLogger.app.info("✅ GitHub Token 已保存")
        } else {
            UserDefaults.standard.removeObject(forKey: "GitHubAccessToken")
            AppLogger.app.info("🗑️ GitHub Token 已清除")
        }
    }

    /// 检查是否已配置 Token
    var hasGitHubToken: Bool {
        githubAccessToken != nil
    }
}
