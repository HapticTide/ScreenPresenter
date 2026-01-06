# Prompt：Transcript Post-Processing Pipeline

你将为 macOS 应用 **ScreenPresenter** 实现一个 **会议记录后处理流水线（Post-Processing Pipeline）**，用于将 **Mic 实时转录文本** 转化为 **高质量、可追溯的会议纪要与总结文档**。

该流水线必须严格分为四阶段，并且 **每一阶段的输入与输出都要可保存、可回放、可 Debug**。

---

## 一、总体目标

构建一条**工程级、可解释、模块化**的文本处理流水线：

```
Raw Transcript (Whisper)
        ↓
Corrected Transcript (LanguageTool)
        ↓
Structured Sections (Marker-based)
        ↓
Summary (LLM: Claude / GPT / Local)
```

最终输出：

- 原始逐字稿（Raw Transcript）
- 纠错后逐字稿（Corrected Transcript）
- 结构化章节（Structured Sections）
- 会议总结文档（Summary / Issues / Actions）
- Markdown 文件（可导出）

---

## 二、设计原则（必须遵守）

1. **职责单一**
   - Whisper：只负责"语音 → 文本"，不做语义修改
   - LanguageTool：只做轻量纠错，不改变语义
   - LLM：只做总结，不参与纠错
2. **中间结果必须持久化**
   - 禁止"直接 Whisper → 总结"
   - Raw / Corrected / Summary 都要落盘
3. **可替换性**
   - Whisper / LanguageTool / LLM 均通过协议抽象
   - 不允许在业务代码中写死某个模型或命令
4. **面向会议场景**
   - 文本是口语、断句混乱、重复多
   - Marker（Issue / Idea / Action）是一级信息源

---

## 三、数据输入（来自 ScreenPresenter 主流程）

### 输入数据结构（已存在，需消费）

```swift
struct MeetingSession {
    let id: UUID
    let language: String          // "zh" / "en" / "auto"
    let chunks: [TranscriptChunk] // Whisper 输出
    let markers: [Marker]         // 人工标记
}
```

其中：

- `TranscriptChunk` 已包含：
  - startTime / endTime
  - rawText
  - confidence
- `Marker` 包含：
  - time
  - kind（issue / idea / action）
  - optional title / detail

---

## 四、Stage 1：Raw Transcript（Whisper 输出处理）

### 目标

- 按时间线拼接 Whisper 的原始输出
- **不做任何语义改动**

### 要求

1. 按 `startTime` 排序
2. 保留原始文本、时间戳、置信度
3. 输出 `raw_transcript.json`

### 输出结构

```json
{
  "sessionId": "...",
  "language": "zh",
  "chunks": [
    {
      "id": "...",
      "start": 12.3,
      "end": 18.9,
      "text": "这个页面点进去会卡一下",
      "confidence": 0.84
    }
  ]
}
```

---

## 五、Stage 2：Corrected Transcript（LanguageTool）

### 目标

将"像人说的话"修成"像人写的话"，但**不改变意思**。

### 使用 LanguageTool 的严格限制

- ✅ 允许：
  - 拼写纠错
  - 标点修正
  - 大小写修正
- ❌ 禁止：
  - 改写句式
  - 合并句子
  - 风格润色

### 执行策略

1. **以 chunk 为单位调用 LanguageTool**
2. 逐条处理，禁止整篇一次性处理
3. 对每条生成 diff（可选但推荐）

### 输出结构

```json
{
  "sessionId": "...",
  "chunks": [
    {
      "id": "...",
      "start": 12.3,
      "end": 18.9,
      "rawText": "这个页面点进去会卡一下",
      "correctedText": "这个页面点进去会卡一下。",
      "appliedRules": ["PUNCTUATION"],
      "confidence": 0.84
    }
  ]
}
```

文件名：`corrected_transcript.json`

---

## 六、Stage 3：结构化预处理（LLM 前）

⚠️ **这是成功与否的关键阶段，不能省略**

### 目标

把"口水话逐字稿"变成 **LLM 能消费的结构化输入**。

### 必须做的事情

#### 1. 按 Marker 切分

- 每个 Marker（Issue / Idea / Action）形成一个 Section
- Section 包含：
  - Marker 时间 ± N 秒内的 chunks
  - 原始 correctedText

#### 2. 无 Marker 的文本

- 按时间窗口（例如 60–120 秒）分段
- 标记为 `context`

#### 3. 控制 token 长度

- 每个 Section 不超过模型上限
- 过长就继续切分

### 中间结构（持久化到文件）

```json
{
  "sections": [
    {
      "type": "issue",
      "time": 133.2,
      "sourceChunkIds": ["uuid1", "uuid2"],
      "text": "..."
    }
  ]
}
```

文件名：`structured_sections.json`

---

## 七、Stage 4：LLM 总结

### 模型职责

- 抽象总结
- 归纳问题
- 提取行动项

### 严格要求

1. **只能基于 corrected transcript**
2. 输出必须结构化，禁止自由发挥
3. 禁止引入原文中不存在的事实

### 推荐 Prompt 模板（给 LLM）

```
你是专业的会议记录助手。
以下内容来自一次产品展示会议的逐字记录（已纠错）。
请根据内容：

1. 提取核心摘要（1-3 句话）
2. 提取发现的问题（Issues）
3. 提取建议或想法（Ideas）
4. 提取明确的行动项（Actions）

规则：
- 只提取原文明确提及的内容
- 不要推测或补充信息
- 保持原文的语言风格
- 输出格式必须为 JSON
```

### 输出结构

```json
{
  "summary": "本次会议主要讨论了首页性能和交互问题。",
  "issues": [
    { "text": "进入详情页时存在明显卡顿", "time": 133.2 }
  ],
  "ideas": [
    { "text": "考虑提前预加载详情页数据", "time": 156.8 }
  ],
  "actions": [
    { "text": "检查详情页首屏渲染性能", "priority": "high", "assignee": null }
  ]
}
```

文件名：`summary.json`

---

## 八、最终导出（Markdown）

### 导出规则

- 使用 corrected transcript
- 使用 LLM 输出的结构化结果
- 严格模板化

### Markdown 结构

```md
# Meeting Notes – {title}

**日期**: {date}
**时长**: {duration}
**语言**: {language}

## Summary
...

## Issues
- [02:13] 进入详情页时存在明显卡顿

## Ideas
- [02:36] 考虑提前预加载详情页数据

## Actions
- [ ] 检查详情页首屏渲染性能 (高优先级)

---

## Transcript

### [00:00–02:00] 开场

- [00:12–00:18] 这个页面点进去会卡一下。
- [00:19–00:25] 对，我也注意到了这个问题。

### [02:00–04:00] 问题讨论
...
```

---

## 九、错误处理与降级策略（必须实现）

| 失败场景 | 降级策略 |
|---------|---------|
| LanguageTool 失败 | 使用 rawText，标记 `corrected=false` |
| LLM 失败 | 跳过 Summary，仍导出逐字稿 + Marker |
| Whisper 部分失败 | 标记低置信度，继续处理 |
| 网络超时 | 重试 3 次，间隔指数退避 |

**核心原则**：任何阶段不得阻塞 UI

---

## 十、技术落地方案

### 10.1 架构设计

#### 核心模块结构

```
ScreenPresenter/
├── Core/
│   ├── Transcript/
│   │   ├── TranscriptPipeline.swift           # 流水线状态机
│   │   ├── TranscriptSession.swift            # 会话数据模型
│   │   ├── TranscriptChunk.swift              # 文本片段模型
│   │   ├── TranscriptMarker.swift             # 标记模型
│   │   └── TranscriptExporter.swift           # Markdown 导出器
│   ├── Transcript/Stages/
│   │   ├── RawTranscriptStage.swift           # Stage 1: 原始转录
│   │   ├── CorrectionStage.swift              # Stage 2: 文本纠错
│   │   ├── StructuringStage.swift             # Stage 3: 结构化
│   │   └── SummarizationStage.swift           # Stage 4: 总结
│   ├── Transcript/Providers/
│   │   ├── WhisperProvider.swift              # Whisper 接口协议
│   │   ├── LocalWhisperProvider.swift         # 本地 Whisper 实现
│   │   ├── CorrectionProvider.swift           # 纠错接口协议
│   │   ├── LanguageToolProvider.swift         # LanguageTool 实现
│   │   ├── SummarizationProvider.swift        # 总结接口协议
│   │   ├── ClaudeProvider.swift               # Claude API 实现
│   │   ├── OpenAIProvider.swift               # OpenAI API 实现
│   │   └── LocalLLMProvider.swift             # 本地 LLM 实现 (Ollama)
│   └── Transcript/Storage/
│       ├── TranscriptStorage.swift            # 存储接口
│       ├── FileTranscriptStorage.swift        # 文件存储实现
│       └── TranscriptFileFormat.swift         # 文件格式定义
```

#### 流水线状态机

```swift
/// 流水线状态
enum PipelineState: Equatable {
    case idle
    case processing(stage: PipelineStage, progress: Double)
    case paused(at: PipelineStage, reason: PauseReason)
    case completed(duration: TimeInterval)
    case failed(stage: PipelineStage, error: PipelineError)
}

/// 流水线阶段
enum PipelineStage: Int, CaseIterable, Comparable {
    case rawTranscript = 1
    case correction = 2
    case structuring = 3
    case summarization = 4
    case export = 5
    
    var displayName: String {
        switch self {
        case .rawTranscript: "转录处理"
        case .correction: "文本纠错"
        case .structuring: "结构化"
        case .summarization: "生成摘要"
        case .export: "导出文档"
        }
    }
}

/// 流水线配置
struct PipelineConfiguration {
    var whisperProvider: WhisperProvider
    var correctionProvider: CorrectionProvider?
    var summarizationProvider: SummarizationProvider?
    var storage: TranscriptStorage
    var language: TranscriptLanguage
    var enableCorrection: Bool = true
    var enableSummarization: Bool = true
    var markerContextWindow: TimeInterval = 30  // Marker 前后上下文秒数
    var maxTokensPerSection: Int = 2000
}
```

### 10.2 依赖选型

| 组件 | 推荐方案 | 备选方案 | 说明 |
|------|---------|---------|------|
| **Whisper** | whisper.cpp (本地) | OpenAI Whisper API | 优先本地，保护隐私 |
| **LanguageTool** | LanguageTool Server (Docker) | LanguageTool Cloud API | 本地部署，无网络依赖 |
| **LLM** | Claude API (claude-sonnet-4-20250514) | OpenAI GPT-4 / Ollama | Claude 中文能力强 |
| **存储** | 本地 JSON 文件 | SQLite | 简单可靠，易于调试 |

### 10.3 Whisper 集成方案

#### 方案 A：whisper.cpp (推荐)

```swift
/// 本地 Whisper 配置
struct LocalWhisperConfig {
    /// 模型路径 (ggml-base.bin / ggml-medium.bin / ggml-large-v3.bin)
    var modelPath: URL
    /// 语言 (auto / zh / en / ja)
    var language: String = "auto"
    /// 实时流式输出
    var streaming: Bool = true
    /// VAD 检测阈值
    var vadThreshold: Float = 0.6
    /// 线程数
    var threads: Int = 4
}

protocol WhisperProvider {
    func transcribe(audioURL: URL) async throws -> [TranscriptChunk]
    func transcribeStream(_ audioStream: AsyncStream<Data>) -> AsyncStream<TranscriptChunk>
    var isAvailable: Bool { get }
    var modelInfo: WhisperModelInfo { get }
}
```

**部署方式**：
1. 内置 whisper.cpp 编译产物到 Resources
2. 模型文件下载到 Application Support
3. 通过 Process 调用或 C 桥接

#### 方案 B：OpenAI Whisper API

```swift
struct WhisperAPIConfig {
    var apiKey: String
    var model: String = "whisper-1"
    var language: String? = nil
    var responseFormat: ResponseFormat = .verboseJson
    
    enum ResponseFormat: String {
        case json
        case verboseJson = "verbose_json"
        case text
        case srt
        case vtt
    }
}
```

### 10.4 LanguageTool 集成方案

#### Docker 本地部署 (推荐)

```bash
# 启动 LanguageTool Server (支持多语言)
docker run -d \
  --name languagetool \
  -p 8081:8010 \
  -e Java_Xms=512m \
  -e Java_Xmx=2g \
  erikvl87/languagetool:latest

# 健康检查
curl -s "http://localhost:8081/v2/check" \
  -d "language=zh-CN" \
  -d "text=这是一个测试" | jq
```

#### Swift 客户端封装

```swift
actor LanguageToolProvider: CorrectionProvider {
    private let baseURL: URL
    private let session: URLSession
    private let disabledRules: Set<String>
    
    init(
        baseURL: URL = URL(string: "http://localhost:8081")!,
        disabledRules: Set<String> = ["WHITESPACE_RULE", "COMMA_PARENTHESIS_WHITESPACE"]
    ) {
        self.baseURL = baseURL
        self.disabledRules = disabledRules
        self.session = URLSession(configuration: .default)
    }
    
    func correct(_ text: String, language: String) async throws -> CorrectionResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("v2/check"), resolvingAgainstBaseURL: false)!
        
        let response = try await session.data(for: buildRequest(text: text, language: language))
        return try parse(response.0)
    }
    
    func healthCheck() async -> Bool {
        do {
            let (_, response) = try await session.data(from: baseURL.appendingPathComponent("v2/languages"))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

### 10.5 LLM 集成方案

#### 协议抽象

```swift
protocol SummarizationProvider {
    func summarize(
        sections: [TranscriptSection],
        language: String,
        options: SummarizationOptions
    ) async throws -> SummarizationResult
    
    var isAvailable: Bool { get }
    var providerName: String { get }
    var estimatedCostPerToken: Double { get }
}

struct SummarizationOptions {
    var maxSummaryLength: Int = 500
    var extractIssues: Bool = true
    var extractIdeas: Bool = true
    var extractActions: Bool = true
    var temperature: Double = 0.3
}

struct SummarizationResult: Codable {
    var summary: String
    var issues: [Issue]
    var ideas: [Idea]
    var actions: [Action]
    var metadata: SummarizationMetadata
    
    struct Issue: Codable {
        var text: String
        var time: TimeInterval?
        var severity: Severity?
        
        enum Severity: String, Codable {
            case low, medium, high, critical
        }
    }
    
    struct Idea: Codable {
        var text: String
        var time: TimeInterval?
    }
    
    struct Action: Codable {
        var text: String
        var priority: Priority
        var assignee: String?
        var deadline: Date?
        
        enum Priority: String, Codable {
            case low, medium, high
        }
    }
    
    struct SummarizationMetadata: Codable {
        var provider: String
        var model: String
        var inputTokens: Int
        var outputTokens: Int
        var latencyMs: Int
        var timestamp: Date
    }
}
```

#### Claude 实现

```swift
actor ClaudeProvider: SummarizationProvider {
    private let apiKey: String
    private let model: String
    private let session: URLSession
    
    private let systemPrompt = """
    你是专业的会议记录助手。根据提供的会议逐字稿，提取以下内容：
    
    1. **摘要** (summary): 用 1-3 句话概括会议核心内容
    2. **问题** (issues): 会议中提到的问题或挑战
    3. **想法** (ideas): 提出的建议、方案或想法
    4. **行动项** (actions): 明确需要执行的任务
    
    输出规则：
    - 必须输出有效的 JSON 格式
    - 只提取原文明确提及的内容，禁止推测
    - 保持原文语言风格
    - 如有时间戳，请关联到对应内容
    
    JSON 格式：
    {
      "summary": "...",
      "issues": [{"text": "...", "time": 123.4, "severity": "high"}],
      "ideas": [{"text": "...", "time": 156.7}],
      "actions": [{"text": "...", "priority": "high", "assignee": null}]
    }
    """
    
    init(apiKey: String, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
        self.session = URLSession(configuration: .default)
    }
    
    func summarize(
        sections: [TranscriptSection],
        language: String,
        options: SummarizationOptions
    ) async throws -> SummarizationResult {
        let content = formatSections(sections)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let response = try await callAPI(
            messages: [
                Message(role: "user", content: "以下是会议记录（语言：\(language)）：\n\n\(content)")
            ]
        )
        
        let latency = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        return try parseResponse(response, latencyMs: latency)
    }
}
```

#### 本地 LLM (Ollama)

```swift
actor OllamaProvider: SummarizationProvider {
    private let baseURL: URL
    private let model: String
    private let session: URLSession
    
    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "qwen2.5:14b"  // 或 llama3.2, mistral
    ) {
        self.baseURL = baseURL
        self.model = model
        self.session = URLSession(configuration: .default)
    }
    
    var isAvailable: Bool {
        get async {
            do {
                let (_, response) = try await session.data(from: baseURL.appendingPathComponent("api/tags"))
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
}
```

### 10.6 存储方案

#### 目录结构

```
~/Library/Application Support/ScreenPresenter/
├── Transcripts/
│   └── {session-id}/
│       ├── metadata.json              # 会话元数据
│       ├── raw_transcript.json        # Stage 1 输出
│       ├── corrected_transcript.json  # Stage 2 输出
│       ├── structured_sections.json   # Stage 3 输出
│       ├── summary.json               # Stage 4 输出
│       ├── pipeline_state.json        # 流水线状态（用于恢复）
│       └── exports/
│           ├── meeting_notes.md       # Markdown 导出
│           └── meeting_notes.pdf      # PDF 导出（可选）
├── Models/
│   └── whisper/
│       └── ggml-base.bin              # Whisper 模型
└── Logs/
    └── transcript_pipeline.log        # 流水线日志
```

#### 存储接口

```swift
protocol TranscriptStorage {
    // 保存阶段输出
    func save<T: Encodable>(_ data: T, stage: PipelineStage, sessionId: UUID) async throws
    
    // 加载阶段输出
    func load<T: Decodable>(_ type: T.Type, stage: PipelineStage, sessionId: UUID) async throws -> T?
    
    // 保存流水线状态（用于恢复）
    func savePipelineState(_ state: PipelineState, sessionId: UUID) async throws
    
    // 加载流水线状态
    func loadPipelineState(sessionId: UUID) async throws -> PipelineState?
    
    // 会话管理
    func listSessions() async throws -> [TranscriptSessionInfo]
    func deleteSession(_ sessionId: UUID) async throws
    func getSessionSize(_ sessionId: UUID) async throws -> Int64
}

struct TranscriptSessionInfo: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var language: String
    var lastCompletedStage: PipelineStage?
    var totalChunks: Int
    var totalMarkers: Int
}
```

### 10.7 UI 集成

#### 转录面板视图

```swift
final class TranscriptPanelView: NSView {
    // MARK: - UI 组件
    
    /// 实时转录文本显示区域
    private let transcriptTextView = NSTextView()
    
    /// Marker 快捷按钮
    private let issueButton = MarkerButton(kind: .issue)
    private let ideaButton = MarkerButton(kind: .idea)
    private let actionButton = MarkerButton(kind: .action)
    
    /// 流水线状态指示器
    private let pipelineStatusView = PipelineStatusView()
    
    /// 导出按钮
    private let exportButton = NSButton()
    
    // MARK: - 回调
    
    var onMarkerAdded: ((TranscriptMarker) -> Void)?
    var onExport: ((ExportFormat) -> Void)?
    var onPipelineControl: ((PipelineControlAction) -> Void)?
    
    // MARK: - 快捷键
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 34 where event.modifierFlags.contains(.command): // Cmd+I
            addMarker(.issue)
        case 31 where event.modifierFlags.contains(.command): // Cmd+O
            addMarker(.idea)
        case 0 where event.modifierFlags.contains(.command):  // Cmd+A
            addMarker(.action)
        default:
            super.keyDown(with: event)
        }
    }
}
```

#### 偏好设置面板

```swift
extension PreferencesWindowController {
    private func createTranscriptTab() -> NSView {
        let container = createSettingsContainer()
        
        // Whisper 设置组
        let whisperGroup = createSettingsGroup(title: "语音识别 (Whisper)", icon: "waveform")
        addGroupRow(whisperGroup, createWhisperModelSelector())
        addGroupRow(whisperGroup, createLanguageSelector())
        addGroupRow(whisperGroup, createVADThresholdSlider())
        container.addArrangedSubview(whisperGroup)
        
        // LanguageTool 设置组
        let ltGroup = createSettingsGroup(title: "文本纠错 (LanguageTool)", icon: "textformat.abc")
        addGroupRow(ltGroup, createLanguageToolURLField())
        addGroupRow(ltGroup, createCorrectionToggle())
        container.addArrangedSubview(ltGroup)
        
        // LLM 设置组
        let llmGroup = createSettingsGroup(title: "智能摘要 (LLM)", icon: "brain.head.profile")
        addGroupRow(llmGroup, createLLMProviderSelector())
        addGroupRow(llmGroup, createAPIKeyField())
        addGroupRow(llmGroup, createModelSelector())
        container.addArrangedSubview(llmGroup)
        
        // 存储设置组
        let storageGroup = createSettingsGroup(title: "存储", icon: "folder")
        addGroupRow(storageGroup, createStoragePathField())
        addGroupRow(storageGroup, createAutoCleanupToggle())
        container.addArrangedSubview(storageGroup)
        
        return container
    }
}
```

### 10.8 性能优化

| 优化点 | 策略 | 预期效果 |
|-------|------|---------|
| **Whisper 并发** | 使用 OperationQueue 限制并发数为 2 | 避免 CPU 过载 |
| **LanguageTool 批处理** | 5-10 个 chunks 合并为一次请求 | 减少 HTTP 开销 |
| **LLM 流式输出** | 使用 Server-Sent Events 流式接收 | 实时更新 UI |
| **存储写入** | 异步写入 + 500ms debounce | 减少磁盘 IO |
| **内存管理** | 分页加载大型逐字稿（每页 100 chunks） | 控制内存占用 |
| **UI 更新** | 使用 Combine 节流（100ms） | 避免 UI 卡顿 |

---

## 十一、ROADMAP

### Phase 1：基础架构 (Week 1-2)

| 任务 | 优先级 | 预估工时 | 交付物 | 验收标准 |
|-----|--------|---------|-------|---------|
| 定义核心数据模型 | P0 | 2d | `TranscriptChunk`, `Marker`, `Session` | 模型编译通过，单测覆盖 |
| 实现流水线状态机 | P0 | 3d | `TranscriptPipeline.swift` | 状态转换正确，可暂停恢复 |
| 实现文件存储层 | P0 | 2d | `FileTranscriptStorage.swift` | 读写一致，支持并发 |
| Provider 协议定义 | P0 | 1d | `*Provider.swift` 协议文件 | 接口清晰，文档完整 |
| 单元测试框架 | P1 | 1d | XCTest 基础用例 | 覆盖核心逻辑 |

**里程碑 1**：流水线骨架可运行，Mock 数据可流转

---

### Phase 2：Stage 1-2 实现 (Week 3-4)

| 任务 | 优先级 | 预估工时 | 交付物 | 验收标准 |
|-----|--------|---------|-------|---------|
| whisper.cpp 集成 | P0 | 4d | `LocalWhisperProvider.swift` | 10 分钟音频转录成功 |
| 模型下载管理 | P0 | 2d | 模型下载 UI + 进度 | 下载/取消/重试正常 |
| 实时转录 UI | P0 | 3d | `TranscriptPanelView.swift` | 实时显示转录文本 |
| LanguageTool Docker 文档 | P0 | 0.5d | `LANGUAGETOOL_SETUP.md` | 一键部署可运行 |
| LanguageTool 客户端 | P0 | 2d | `LanguageToolProvider.swift` | 中英文纠错正确 |
| 纠错 diff 高亮显示 | P1 | 2d | UI 高亮修改内容 | 用户可见修改差异 |

**里程碑 2**：可实时转录并纠错，中间结果持久化

---

### Phase 3：Stage 3-4 实现 (Week 5-6)

| 任务 | 优先级 | 预估工时 | 交付物 | 验收标准 |
|-----|--------|---------|-------|---------|
| 结构化预处理 | P0 | 3d | `StructuringStage.swift` | 按 Marker 正确切分 |
| Marker 标记 UI | P0 | 2d | Issue/Idea/Action 按钮 | 快捷键可用 |
| Claude API 客户端 | P0 | 2d | `ClaudeProvider.swift` | API 调用成功 |
| 摘要 JSON 解析 | P0 | 1d | 解析 + 校验逻辑 | 容错处理健壮 |
| OpenAI API 客户端 | P1 | 1d | `OpenAIProvider.swift` | 作为备选方案 |
| Ollama 客户端 | P2 | 2d | `OllamaProvider.swift` | 本地 LLM 可用 |
| 摘要结果 UI | P0 | 2d | Summary 面板 | 展示 Issues/Ideas/Actions |

**里程碑 3**：完整流水线端到端可运行

---

### Phase 4：导出与设置 (Week 7)

| 任务 | 优先级 | 预估工时 | 交付物 | 验收标准 |
|-----|--------|---------|-------|---------|
| Markdown 导出 | P0 | 2d | `TranscriptExporter.swift` | 格式正确，可读性好 |
| 偏好设置 UI | P0 | 2d | Transcript 设置 Tab | 所有配置可修改 |
| 历史会话列表 | P1 | 1.5d | 会话管理界面 | 查看/删除/恢复 |
| 会话恢复功能 | P1 | 1d | 断点续传逻辑 | 重启后可继续 |
| 快捷键绑定 | P1 | 0.5d | 全局快捷键配置 | Cmd+I/O/A 可用 |

**里程碑 4**：功能完整，用户可配置

---

### Phase 5：优化与稳定 (Week 8)

| 任务 | 优先级 | 预估工时 | 交付物 | 验收标准 |
|-----|--------|---------|-------|---------|
| 性能优化 | P0 | 3d | 优化后的代码 | CPU < 50%, 内存 < 500MB |
| 错误处理完善 | P0 | 2d | 降级策略实现 | 任意阶段失败可降级 |
| 端到端测试 | P0 | 2d | 集成测试用例 | 10 个场景通过 |
| 用户文档 | P1 | 1d | README、使用指南 | 新用户可自助 |
| 发布准备 | P1 | 1d | 版本号、Changelog | 可发布状态 |

**里程碑 5**：生产就绪，可发布

---

## 十二、交付清单

### 代码交付

- [ ] `TranscriptPipeline.swift` - 流水线状态机
- [ ] `TranscriptSession.swift` - 会话模型
- [ ] `TranscriptChunk.swift` - 文本片段模型
- [ ] `TranscriptMarker.swift` - 标记模型
- [ ] `RawTranscriptStage.swift` - Stage 1
- [ ] `CorrectionStage.swift` - Stage 2
- [ ] `StructuringStage.swift` - Stage 3
- [ ] `SummarizationStage.swift` - Stage 4
- [ ] `TranscriptExporter.swift` - 导出器
- [ ] `WhisperProvider.swift` - Whisper 协议
- [ ] `LocalWhisperProvider.swift` - 本地实现
- [ ] `CorrectionProvider.swift` - 纠错协议
- [ ] `LanguageToolProvider.swift` - LanguageTool 实现
- [ ] `SummarizationProvider.swift` - 总结协议
- [ ] `ClaudeProvider.swift` - Claude 实现
- [ ] `FileTranscriptStorage.swift` - 存储实现
- [ ] `TranscriptPanelView.swift` - 转录面板 UI
- [ ] `PipelineStatusView.swift` - 状态指示器

### 文档交付

- [ ] `README.md` - 功能说明 + 快速开始
- [ ] `ARCHITECTURE.md` - 架构设计文档
- [ ] `SETUP.md` - 环境配置指南（Docker、模型）
- [ ] `API.md` - Provider 接口文档
- [ ] `CHANGELOG.md` - 版本变更日志

### 测试交付

- [ ] 单元测试（各 Stage、Provider、Storage）
- [ ] 集成测试（端到端流水线）
- [ ] Mock 数据集（用于演示和测试）

---

## 十三、验收标准

| 场景 | 输入 | 预期结果 |
|-----|------|---------|
| 录制 10 分钟会议 | 真实音频 | Raw transcript 正确生成并持久化 |
| 中英混合文本 | "我们来看这个 API 调用" | LanguageTool 正确处理，不破坏混合文本 |
| 标记 3 个 Issue | 用户点击 Issue 按钮 | Summary 包含所有标记内容及时间戳 |
| LLM 服务不可用 | 网络断开 | 仍能导出逐字稿 + Marker 的 Markdown |
| 重启应用 | 关闭再打开 | 可加载历史会话，继续处理未完成阶段 |
| 长会议 (60 分钟) | 大量文本 | 内存 < 500MB，UI 不卡顿 |
| 快速标记 | 连续按 Cmd+I 5 次 | 所有 Marker 正确记录 |

---

## 十四、风险与应对

| 风险 | 概率 | 影响 | 应对措施 |
|-----|------|-----|---------|
| whisper.cpp 编译/兼容性问题 | 中 | 高 | 提前验证 Intel/Apple Silicon，准备 OpenAI API 备选 |
| LanguageTool 中文效果差 | 中 | 中 | 中文场景可跳过或使用 LLM 直接纠错 |
| LLM API 成本高 | 中 | 中 | 支持本地 Ollama，提供 token 估算 |
| LLM 输出格式不稳定 | 中 | 中 | 严格 JSON Schema 校验 + 重试机制 |
| 长会议内存溢出 | 低 | 高 | 分页加载、流式处理、定期写盘 |
| 实时转录延迟高 | 低 | 中 | 使用更小模型（base），牺牲准确性换速度 |
