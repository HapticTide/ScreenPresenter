# Prompt：ScreenPresenter「电视端预补偿」实现方案

## 角色与背景

你是一个 **资深 macOS / Metal / 图形管线工程 Agent**，正在为 ScreenPresenter 增加一套 **显示终端预补偿系统**，用于对冲电视面板与电视端图像算法导致的颜色与亮度失真。

### 已知事实

- ScreenPresenter 本地预览颜色 **是正确的**
- 失真仅发生在 **电视面板 + 电视端图像处理**
- 不涉及视频链路、编码、色彩空间错误
- 目标是 **预补偿（pre-compensation）**，而非"色彩增强"

### 现有渲染架构（必须兼容）

```
CVPixelBuffer (BGRA8)
     ↓
CVMetalTextureCache → MTLTexture
     ↓
SingleDeviceRenderView / MetalRenderer
     ↓
CAMetalLayer → 屏幕显示
```

- 渲染入口：`SingleDeviceRenderView.updateTexture(from:)`
- 着色器：内联 Metal Shader（vertexShader / fragmentShader）
- 纹理格式：`.bgra8Unorm`

------

## 总体目标

实现一套 **基于 1D LUT 的实时颜色预补偿系统**，特点：

- **GPU（Metal）实时处理**
- 可调 Gamma / 黑位 / 高光 / 色温 / 饱和度
- 支持 **Profile（按电视/输出设备保存）**
- 可在任意时刻一键启用 / 禁用（AB 对比）
- 架构上为未来 3D LUT 扩展预留接口

------

## 一、系统结构设计

### 1. ColorCompensationFilter（核心处理器）

**文件**: `Core/Rendering/ColorCompensation/ColorCompensationFilter.swift`

职责：
- 管理 1D LUT 纹理（MTLTexture1D）
- 管理补偿参数 Uniform Buffer
- 提供 Shader 函数供现有渲染管线调用
- 支持实时参数更新（线程安全）

```swift
protocol ColorCompensationFilterProtocol {
    var isEnabled: Bool { get set }
    var profile: ColorProfile { get set }
    
    /// 创建/更新 LUT 纹理
    func updateLUT()
    
    /// 获取 Shader 参数 Buffer
    func getUniformBuffer() -> MTLBuffer?
    
    /// 获取 LUT 纹理
    func getLUTTexture() -> MTLTexture?
}
```

### 2. ColorProfile（参数模型）

**文件**: `Core/Rendering/ColorCompensation/ColorProfile.swift`

```swift
struct ColorProfile: Codable, Equatable {
    var name: String = "Default"
    
    // === 亮度曲线参数 ===
    var gamma: Float = 1.0          // 范围: 0.5 ~ 2.0, 默认 1.0
    var blackLift: Float = 0.0      // 范围: -0.1 ~ 0.1, 默认 0.0
    var whiteClip: Float = 1.0      // 范围: 0.9 ~ 1.1, 默认 1.0
    var highlightRollOff: Float = 0.0 // 范围: 0.0 ~ 0.5, 默认 0.0
    
    // === 色彩参数 ===
    var temperature: Float = 0.0    // 范围: -1.0(冷) ~ 1.0(暖), 默认 0.0
    var tint: Float = 0.0           // 范围: -1.0(绿) ~ 1.0(品红), 默认 0.0
    var saturation: Float = 1.0     // 范围: 0.0 ~ 2.0, 默认 1.0
    
    // === 预设工厂方法 ===
    static let neutral = ColorProfile()
    static let coldTV: ColorProfile     // 偏冷电视预设
    static let grayishTV: ColorProfile  // 发灰电视预设
    static let oversaturatedTV: ColorProfile // 过饱和电视预设
}
```

### 3. ColorProfileManager（配置管理）

**文件**: `Core/Rendering/ColorCompensation/ColorProfileManager.swift`

职责：
- Profile CRUD 操作
- 持久化存储（UserDefaults / JSON 文件）
- 根据显示器特征自动匹配 Profile

```swift
final class ColorProfileManager {
    static let shared = ColorProfileManager()
    
    var currentProfile: ColorProfile
    var allProfiles: [ColorProfile]
    
    func save(_ profile: ColorProfile)
    func delete(_ profile: ColorProfile)
    func loadProfileForDisplay(_ displayID: CGDirectDisplayID) -> ColorProfile?
}
```

------

## 二、1D LUT 实现规范

### LUT 规格

| 属性 | 值 |
|------|-----|
| 长度 | 256 |
| 通道 | R / G / B 各一条曲线 |
| 数值范围 | 0.0 ~ 1.0 (Float) |
| 存储格式 | `MTLTexture` (`.r16Float`, 256x1, 3 个纹理) 或 `.rgba16Float` 256x1 单纹理 |

### LUT 生成算法

```swift
/// 生成单通道 LUT 曲线
/// - Parameters:
///   - gamma: 伽马值 (1.0 = 线性)
///   - blackLift: 黑位提升 (输出 = max(blackLift, 原值))
///   - whiteClip: 白点裁切 (输出 = min(whiteClip, 原值))
///   - rollOff: 高光滚降系数 (柔化高光过渡)
func generateLUT(
    gamma: Float,
    blackLift: Float,
    whiteClip: Float,
    rollOff: Float
) -> [Float] {
    var lut = [Float](repeating: 0, count: 256)
    
    for i in 0..<256 {
        var x = Float(i) / 255.0
        
        // 1. 应用 Gamma
        x = pow(x, gamma)
        
        // 2. 应用 Black Lift (提升暗部)
        x = x * (1.0 - blackLift) + blackLift
        
        // 3. 应用 High Light Roll-off (压缩高光)
        if rollOff > 0 && x > (1.0 - rollOff) {
            let t = (x - (1.0 - rollOff)) / rollOff
            x = (1.0 - rollOff) + rollOff * (1.0 - exp(-t * 2.0)) / (1.0 - exp(-2.0))
        }
        
        // 4. 应用 White Clip
        x = min(x, whiteClip)
        
        // 5. 钳位到有效范围
        lut[i] = max(0.0, min(1.0, x))
    }
    
    return lut
}
```

------

## 三、Metal Shader 实现

### 方案：扩展现有 Fragment Shader

在 `MetalRenderer.swift` / `SingleDeviceRenderView.swift` 的 Shader 中增加颜色补偿逻辑：

```metal
#include <metal_stdlib>
using namespace metal;

// === 颜色补偿参数 ===
struct ColorCompensationParams {
    float temperature;      // 色温偏移
    float tint;             // 色调偏移
    float saturation;       // 饱和度
    bool enabled;           // 是否启用
};

// === sRGB <-> Linear 转换 ===
float srgbToLinear(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0/2.4) - 0.055;
}

float3 srgbToLinear(float3 c) {
    return float3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
}

float3 linearToSrgb(float3 c) {
    return float3(linearToSrgb(c.r), linearToSrgb(c.g), linearToSrgb(c.b));
}

// === 应用 1D LUT ===
float3 applyLUT(float3 color, 
                texture1d<float> lutR,
                texture1d<float> lutG,
                texture1d<float> lutB,
                sampler s) {
    return float3(
        lutR.sample(s, color.r).r,
        lutG.sample(s, color.g).r,
        lutB.sample(s, color.b).r
    );
}

// === 应用色温 (简化的 RGB 偏移) ===
float3 applyTemperature(float3 color, float temp, float tint) {
    // 色温：暖 = +R -B, 冷 = -R +B
    color.r += temp * 0.1;
    color.b -= temp * 0.1;
    // 色调：绿 = +G, 品红 = -G +R +B
    color.g += tint * 0.05;
    return clamp(color, 0.0, 1.0);
}

// === 应用饱和度 ===
float3 applySaturation(float3 color, float sat) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    return mix(float3(luma), color, sat);
}

// === 主处理函数 ===
float4 applyColorCompensation(
    float4 inputColor,
    constant ColorCompensationParams &params,
    texture1d<float> lutR,
    texture1d<float> lutG,
    texture1d<float> lutB,
    sampler lutSampler
) {
    if (!params.enabled) {
        return inputColor;
    }
    
    float3 color = inputColor.rgb;
    
    // 1. sRGB → Linear (输入假定为 sRGB)
    color = srgbToLinear(color);
    
    // 2. 应用 1D LUT (在 Linear 空间)
    color = applyLUT(color, lutR, lutG, lutB, lutSampler);
    
    // 3. 应用色温/色调
    color = applyTemperature(color, params.temperature, params.tint);
    
    // 4. 应用饱和度
    color = applySaturation(color, params.saturation);
    
    // 5. Linear → sRGB
    color = linearToSrgb(color);
    
    return float4(color, inputColor.a);
}
```

### 集成点

修改 `SingleDeviceRenderView` 的 Fragment Shader：

```metal
fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    texture1d<float> lutR [[texture(1)]],
    texture1d<float> lutG [[texture(2)]],
    texture1d<float> lutB [[texture(3)]],
    sampler textureSampler [[sampler(0)]],
    sampler lutSampler [[sampler(1)]],
    constant RoundedRectParams &rectParams [[buffer(0)]],
    constant ColorCompensationParams &colorParams [[buffer(1)]]
) {
    float4 color = texture.sample(textureSampler, in.texCoord);
    
    // 应用颜色补偿
    color = applyColorCompensation(color, colorParams, lutR, lutG, lutB, lutSampler);
    
    // 应用圆角 (现有逻辑)
    // ...
    
    return color;
}
```

------

## 四、校准向导（Calibration Wizard）

### Step 1：暗部灰阶校准

**目标**：确保暗部细节可见

**测试图案**：
```
┌─────────────────────────────────────┐
│  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  │
│  0  4  8  12 16 20 24 28 32 36 40  │  ← 灰阶条 (0-40/255)
│                                     │
│  [Black Lift ─────●─────]  0.00    │
│  [Gamma      ─────●─────]  1.00    │
│                                     │
│  提示：调整直到能区分相邻灰阶块      │
└─────────────────────────────────────┘
```

### Step 2：中间调与高光校准

**目标**：确保整体对比度合适

**测试图案**：
```
┌─────────────────────────────────────┐
│  渐变条：0% ████████████████ 100%   │
│                                     │
│  [Gamma          ─────●─────] 1.00 │
│  [Highlight Roll ─────●─────] 0.00 │
│  [White Clip     ─────●─────] 1.00 │
│                                     │
│  提示：调整直到高光不过曝、暗部不死黑 │
└─────────────────────────────────────┘
```

### Step 3：色温与饱和度校准

**目标**：确保肤色自然、色彩准确

**测试图案**：
```
┌─────────────────────────────────────┐
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │肤色1 │  │肤色2 │  │肤色3 │      │  ← 肤色参考块
│  └──────┘  └──────┘  └──────┘      │
│                                     │
│  🔴 🟢 🔵 🟡 🟣 ⚫ ⚪              │  ← 基础色块
│                                     │
│  [Temperature ─────●─────]  0.00   │
│  [Tint        ─────●─────]  0.00   │
│  [Saturation  ─────●─────]  1.00   │
└─────────────────────────────────────┘
```

------

## 五、UI 设计

### 颜色补偿控制面板

**入口**：菜单 → 视图 → 颜色补偿 / 快捷键 ⌘⇧C

```
┌─────────────────────────────────────┐
│  颜色补偿                    [×]   │
├─────────────────────────────────────┤
│  ☑ 启用补偿              [AB对比]  │
├─────────────────────────────────────┤
│  预设：[Default         ▼] [保存]  │
├─────────────────────────────────────┤
│  亮度曲线                          │
│  Gamma          [─────●─────] 1.00 │
│  黑位提升       [─────●─────] 0.00 │
│  白点裁切       [─────●─────] 1.00 │
│  高光滚降       [─────●─────] 0.00 │
├─────────────────────────────────────┤
│  色彩调整                          │
│  色温 (冷↔暖)   [─────●─────] 0.00 │
│  色调 (绿↔紫)   [─────●─────] 0.00 │
│  饱和度         [─────●─────] 1.00 │
├─────────────────────────────────────┤
│  快速预设                          │
│  [偏冷电视] [发灰电视] [过饱和电视] │
├─────────────────────────────────────┤
│  [校准向导...]          [重置默认] │
└─────────────────────────────────────┘
```

### 交互规范

| 操作 | 行为 |
|------|------|
| 拖动滑杆 | 实时预览，无延迟 |
| AB 对比按钮 | 按住时 Bypass，松开恢复 |
| 保存预设 | 弹出命名对话框 |
| 校准向导 | 打开单独窗口，全屏测试图案 |

------

## 六、文件结构

```
ScreenPresenter/
├── Core/
│   └── Rendering/
│       └── ColorCompensation/
│           ├── ColorCompensationFilter.swift    // 核心处理器
│           ├── ColorProfile.swift               // 参数模型
│           ├── ColorProfileManager.swift        // 配置管理
│           ├── LUTGenerator.swift               // LUT 生成算法
│           └── ColorCompensationShaders.metal   // Shader 代码 (可选，或内联)
├── Views/
│   └── ColorCompensation/
│       ├── ColorCompensationPanel.swift         // 控制面板
│       └── CalibrationWizardWindow.swift        // 校准向导
└── Resources/
    └── CalibrationPatterns/                     // 校准测试图案 (可选)
```

------

## 七、性能要求

| 指标 | 要求 |
|------|------|
| 额外延迟 | < 1ms |
| GPU 负载增加 | < 5% |
| 内存占用 | < 1MB (LUT 纹理) |
| 参数更新 | 不产生可见闪变 |

### 性能优化策略

1. **LUT 纹理**：使用 `.r16Float` 格式，每通道 256 个采样点，总计约 1.5KB
2. **参数 Buffer**：使用 Triple Buffering 避免 CPU-GPU 同步等待
3. **Bypass 模式**：通过 Shader 分支跳过所有处理，零成本

------

## 八、扩展性设计

### Protocol 抽象

```swift
protocol ColorFilterProtocol {
    var isEnabled: Bool { get set }
    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture
}

// 当前实现
class LUT1DColorFilter: ColorFilterProtocol { ... }

// 未来扩展
class LUT3DColorFilter: ColorFilterProtocol { ... }
```

### 禁止引入的复杂度

- ❌ 3D LUT 解析/加载
- ❌ .cube 文件支持
- ❌ 四面体插值算法

------

## 九、交付清单

| 序号 | 交付物 | 说明 |
|------|--------|------|
| 1 | `ColorProfile.swift` | 参数模型 + 预设 |
| 2 | `LUTGenerator.swift` | LUT 生成算法 |
| 3 | `ColorCompensationFilter.swift` | Metal 纹理/Buffer 管理 |
| 4 | Shader 代码 | 集成到现有渲染管线 |
| 5 | `ColorCompensationPanel.swift` | 控制面板 UI |
| 6 | `CalibrationWizardWindow.swift` | 校准向导 |
| 7 | `ColorProfileManager.swift` | 持久化存储 |

------

## ⚠️ 明确禁止

- ❌ 不引入 ICC / ColorSync 依赖
- ❌ 不做"自动校色"
- ❌ 不宣称"色彩科学级准确"
- ❌ 不依赖电视型号数据库
- ❌ 不修改现有渲染管线的核心架构

------

## 结束语

这不是一个"调色滤镜"，这是一个 **工程级显示终端预补偿系统**。
**稳定、可控、可理解** 优先于"理论完美"。

**实现优先级**：
1. 🔴 P0：ColorProfile + LUT 生成 + Shader 集成
2. 🟡 P1：控制面板 UI + 实时预览
3. 🟢 P2：校准向导 + 预设管理

