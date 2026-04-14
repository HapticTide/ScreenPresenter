//
//  DeviceModel.swift
//  ScreenPresenter
//
//  Created by Sun on 2025/12/23.
//
//  设备型号定义
//  包含各代 iPhone/Android 设备的外观参数
//
//  规格数据参考:
//  - https://www.screensizes.app/
//  - Apple Human Interface Guidelines
//  - 各代 iPhone 实测数据
//

import AppKit

// MARK: - 设备型号定义

/// 设备型号，包含具体设备的外观参数
/// 不同代 iPhone 的参数按照真实设备规格实现
///
/// 数据来源: https://www.screensizes.app/
enum DeviceModel: Equatable {
    // MARK: - iPhone 动态岛系列

    /// iPhone 17 Pro / 17 Pro Max (2025)
    /// - 17 Pro: 6.3" 2622×1206 @460ppi, 边框预计 ~1.0mm
    /// - 17 Pro Max: 6.9" 2868×1320 @460ppi, 边框预计 ~1.0mm
    case iPhone17Pro

    /// iPhone 17 / 17 Plus (2025)
    /// - 17: 6.3" 2622×1206 @460ppi
    /// - 17 Plus: 6.7" (预计)
    case iPhone17

    /// iPhone Air (2025) - 超薄设计
    /// - 6.6" 2740×1280 @460ppi
    case iPhoneAir

    /// iPhone 16 Pro / 16 Pro Max (2024)
    /// - 16 Pro: 6.3" 2622×1206 @460ppi, 设备宽 71.5mm, 边框 1.15mm
    /// - 16 Pro Max: 6.9" 2868×1320 @460ppi, 设备宽 77.6mm, 边框 1.15mm
    case iPhone16Pro

    /// iPhone 16 / 16 Plus (2024)
    /// - 16: 6.1" 2556×1179 @460ppi, 设备宽 71.6mm, 边框 1.85mm
    /// - 16 Plus: 6.7" 2796×1290 @460ppi, 设备宽 77.8mm, 边框 1.85mm
    case iPhone16

    /// iPhone 15 Pro / 15 Pro Max (2023)
    /// - 15 Pro: 6.1" 2556×1179 @460ppi, 设备宽 70.6mm, 边框 1.55mm
    /// - 15 Pro Max: 6.7" 2796×1290 @460ppi, 设备宽 76.7mm, 边框 1.55mm
    case iPhone15Pro

    /// iPhone 15 / 15 Plus (2023)
    /// - 15: 6.1" 2556×1179 @460ppi, 设备宽 71.6mm, 边框 1.80mm
    /// - 15 Plus: 6.7" 2796×1290 @460ppi, 设备宽 77.8mm, 边框 1.80mm
    case iPhone15

    /// iPhone 14 Pro / 14 Pro Max (2022) - 首款动态岛
    /// - 14 Pro: 6.1" 2556×1179 @460ppi, 设备宽 71.5mm, 边框 1.95mm
    /// - 14 Pro Max: 6.7" 2796×1290 @460ppi, 设备宽 77.6mm, 边框 1.95mm
    case iPhone14Pro

    // MARK: - iPhone 刘海屏系列

    /// iPhone 16e (2025) - 刘海屏
    /// - 6.1" 2532×1170 @460ppi
    case iPhone16e

    /// iPhone 14 / 14 Plus (2022) - 小刘海
    /// - 14: 6.1" 2532×1170 @460ppi, 设备宽 71.5mm, 边框 2.39mm
    /// - 14 Plus: 6.7" 2778×1284 @458ppi, 设备宽 78.1mm, 边框 2.39mm
    case iPhone14

    /// iPhone 13 / 13 mini (2021) - 刘海比 12 系列小 20%
    /// - 13: 6.1" 2532×1170 @460ppi, 设备宽 71.5mm, 边框 2.40mm
    /// - 13 mini: 5.4" 2340×1080 @476ppi, 设备宽 64.2mm, 边框 2.20mm
    case iPhone13

    /// iPhone 13 Pro / 13 Pro Max (2021)
    /// - 13 Pro: 6.1" 2532×1170 @460ppi, 设备宽 71.5mm, 边框 2.40mm
    /// - 13 Pro Max: 6.7" 2778×1284 @458ppi, 设备宽 78.1mm, 边框 2.40mm
    case iPhone13Pro

    /// iPhone 12 系列 (2020) - 直角边框设计
    /// - 12: 6.1" 2532×1170 @460ppi, 设备宽 71.5mm, 边框 2.65mm
    /// - 12 Pro Max: 6.7" 2778×1284 @458ppi, 设备宽 78.1mm, 边框 2.65mm
    case iPhone12

    /// iPhone 11 系列 (2019) - 圆角边框
    /// - 11: 6.1" 1792×828 @326ppi, 设备宽 75.7mm, 边框 3.50mm
    /// - 11 Pro Max: 6.5" 2688×1242 @458ppi, 设备宽 77.8mm, 边框 3.50mm
    case iPhone11

    /// iPhone X / XS / XR (2017-2018) - 首款刘海屏
    /// - X: 5.8" 2436×1125 @458ppi, 设备宽 70.9mm, 边框 4.00mm
    /// - XS Max: 6.5" 2688×1242 @458ppi, 设备宽 77.4mm, 边框 4.00mm
    /// - XR: 6.1" 1792×828 @326ppi, 设备宽 75.7mm, 边框 4.50mm
    case iPhoneX

    // MARK: - iPhone Home 键系列

    /// iPhone SE (所有代) - 4.7" 1334×750 @326ppi
    /// 设备宽 67.3mm, 边框 4.00mm (左右), 顶部/底部更宽
    case iPhoneSE

    /// iPhone 8 / 8 Plus 及更早
    /// - 8: 4.7" 1334×750 @326ppi, 设备宽 67.3mm
    /// - 8 Plus: 5.5" 1920×1080 @401ppi, 设备宽 78.1mm
    case iPhoneLegacy

    // MARK: - iPhone 通用

    /// iPhone 通用（未识别具体型号时使用动态岛样式）
    case iPhoneGeneric

    // MARK: - Android 三星系列

    /// 三星 Galaxy S 系列 (打孔屏，居中) - S21/S22/S23/S24/S25
    case samsungGalaxyS
    /// 三星 Galaxy S Ultra 系列 - 大屏旗舰
    case samsungGalaxySUltra
    /// 三星 Galaxy A 系列 - 中端机型
    case samsungGalaxyA
    /// 三星 Galaxy Note 系列 - 大屏商务
    case samsungGalaxyNote
    /// 三星 Galaxy Z Fold (折叠屏展开)
    case samsungGalaxyFold
    /// 三星 Galaxy Z Flip (折叠屏翻盖)
    case samsungGalaxyFlip

    // MARK: - Android Google 系列

    /// Google Pixel 系列 (打孔屏，左上角) - Pixel 6/7/8/9
    case googlePixel
    /// Google Pixel Pro 系列 - 大屏旗舰
    case googlePixelPro
    /// Google Pixel Fold - 折叠屏
    case googlePixelFold
    /// Google Pixel A 系列 - 中端机型
    case googlePixelA

    // MARK: - Android 小米系列

    /// 小米数字系列 - Mi 12/13/14/15
    case xiaomiMi
    /// 小米 Ultra 系列 - 顶级旗舰
    case xiaomiUltra
    /// 小米 MIX 系列 - 全面屏先驱
    case xiaomiMix
    /// Redmi 系列 - 性价比之选
    case redmi
    /// Redmi Note 系列 - 千元机皇
    case redmiNote
    /// Redmi K 系列 - 性能旗舰
    case redmiK
    /// POCO 系列 - 性价比旗舰
    case poco

    // MARK: - Android 一加系列

    /// 一加数字系列 - OnePlus 10/11/12/13
    case oneplus
    /// 一加 Ace 系列 - 性能旗舰
    case oneplusAce
    /// 一加 Nord 系列 - 中端机型
    case oneplusNord

    // MARK: - Android OPPO 系列

    /// OPPO Find 系列 - 旗舰机型
    case oppoFind
    /// OPPO Find X 系列 - 顶级旗舰
    case oppoFindX
    /// OPPO Reno 系列 - 影像旗舰
    case oppoReno
    /// OPPO A 系列 - 中端机型
    case oppoA

    // MARK: - Android Vivo 系列

    /// Vivo X 系列 - 影像旗舰
    case vivoX
    /// Vivo X Fold 系列 - 折叠旗舰
    case vivoXFold
    /// Vivo S 系列 - 自拍旗舰
    case vivoS
    /// Vivo Y 系列 - 中端机型
    case vivoY
    /// iQOO 系列 - 游戏旗舰
    case iqoo
    /// iQOO Neo 系列 - 性价比旗舰
    case iqooNeo

    // MARK: - Android 华为/荣耀系列

    /// 华为 P 系列 - 影像旗舰
    case huaweiP
    /// 华为 Mate 系列 - 商务旗舰
    case huaweiMate
    /// 华为 Mate X 系列 - 折叠旗舰
    case huaweiMateX
    /// 华为 nova 系列 - 时尚中端
    case huaweiNova
    /// 荣耀数字系列 - Honor 90/100
    case honor
    /// 荣耀 Magic 系列 - 旗舰机型
    case honorMagic
    /// 荣耀 X 系列 - 中端机型
    case honorX

    // MARK: - Android Realme 系列

    /// Realme GT 系列 - 性能旗舰
    case realmeGT
    /// Realme 数字系列 - 中端机型
    case realme

    // MARK: - Android Sony 系列

    /// Sony Xperia 1 系列 - 影像旗舰 (21:9 带状屏)
    case sonyXperia1
    /// Sony Xperia 5 系列 - 紧凑旗舰 (21:9 带状屏)
    case sonyXperia5
    /// Sony Xperia 10 系列 - 中端机型
    case sonyXperia10

    // MARK: - Android Motorola 系列

    /// Motorola Edge 系列 - 旗舰机型
    case motorolaEdge
    /// Motorola Razr 系列 - 折叠翻盖
    case motorolaRazr
    /// Moto G 系列 - 中端机型
    case motoG

    // MARK: - Android ASUS 系列

    /// ASUS ROG Phone 系列 - 游戏旗舰
    case asusROG
    /// ASUS Zenfone 系列 - 紧凑旗舰
    case asusZenfone

    // MARK: - Android 游戏手机系列

    /// Nubia Red Magic 系列 - 游戏旗舰
    case nubiaRedMagic
    /// Black Shark 黑鲨系列 - 游戏旗舰
    case blackShark
    /// Lenovo Legion 系列 - 游戏旗舰
    case lenovoLegion

    // MARK: - Android 其他品牌

    /// 魅族系列
    case meizu
    /// Nothing Phone 系列 - 透明设计
    case nothingPhone
    /// TCL 系列
    case tcl
    /// ZTE 系列
    case zte
    /// 传音 (Infinix/Tecno/itel)
    case transsion
    /// Android 通用
    case androidGeneric

    // MARK: - 通用

    /// 完全未知设备
    case unknown
}

// MARK: - 屏幕参数

extension DeviceModel {
    /// 屏幕圆角半径比例（相对于屏幕宽度）
    /// 数据来源: Telegram DeviceMetrics, Apple Human Interface Guidelines
    ///
    /// 注意：
    /// 当前部分 case 合并了同代不同尺寸机型，下面的比例按本项目
    /// `defaultAspectRatio` 实际采用的代表机型宽度换算，而不是按家族中所有机型共用同一值。
    ///
    /// | 当前 case | Telegram 圆角 (pt) | 代表宽度 (pt) | 比例 |
    /// |----------|------------------|--------------|------|
    /// | iPhone 16 Pro Max | 62 | 440 | 0.1409 |
    /// | iPhone Air | 62 | 420 | 0.1476 |
    /// | iPhone 14/15 Pro Max 家族 case | 55 | 430 | 0.1279 |
    /// | iPhone 14/13 Pro Max / 12 Pro Max 家族 case | 53 | 428 | 0.1238 |
    /// | iPhone 13 / 16e | 47 | 390 | 0.1205 |
    /// | iPhone 12 mini | 44 | 360 | 0.1222 |
    /// | iPhone 11 / XR / XS Max 家族 case | 41.5 | 414 | 0.1002 |
    /// | iPhone X / XS | 39 | 375 | 0.1040 |
    var screenCornerRadiusRatio: CGFloat {
        switch self {
        // iPhone 17 Pro - 暂按 16 Pro Max 的口径估算
        case .iPhone17Pro:
            0.1409
        // iPhone 17 - 暂沿用当前估算值
        case .iPhone17:
            0.140
        // iPhone Air - 62pt / 420pt
        case .iPhoneAir:
            0.1476
        // iPhone 16 Pro - 当前 case 使用 16 Pro Max 宽度，62pt / 440pt
        case .iPhone16Pro:
            0.1409
        // iPhone 16 - 当前 case 使用 Plus 宽度，按 55pt / 430pt 估算
        case .iPhone16:
            0.1279
        // iPhone 16e - 类似 iPhone 14 / 13，47pt / 390pt
        case .iPhone16e:
            0.1205
        // iPhone 15 Pro - 当前 case 使用 Pro Max 宽度，按 55pt / 430pt 估算
        case .iPhone15Pro:
            0.1279
        // iPhone 15 - 当前 case 使用 Plus 宽度，按 55pt / 430pt 估算
        case .iPhone15:
            0.1279
        // iPhone 14 Pro - 当前 case 使用 14 Pro Max 宽度，55pt / 430pt
        case .iPhone14Pro:
            0.1279
        // iPhone 14 - 当前 case 使用 14 Plus 宽度，53pt / 428pt
        case .iPhone14:
            0.1238
        // iPhone 13 - 47pt / 390pt
        case .iPhone13:
            0.1205
        // iPhone 13 Pro / 13 Pro Max - 当前 case 使用 Pro Max 宽度，53pt / 428pt
        case .iPhone13Pro:
            0.1238
        // iPhone 12 / 12 Pro Max - 当前 case 使用 Pro Max 宽度，53pt / 428pt
        case .iPhone12:
            0.1238
        // iPhone 11 / 11 Pro Max - 当前 case 使用 414pt 宽度，按 41.5pt / 414pt
        case .iPhone11:
            0.1002
        // iPhone X/XS/XR - 当前 case 使用 414pt 家族宽度，按 41.5pt / 414pt
        case .iPhoneX:
            0.1002
        // iPhone SE / Legacy - 无屏幕圆角
        case .iPhoneSE, .iPhoneLegacy:
            0.0
        // iPhone 通用 - 使用 Pro 系列参数
        case .iPhoneGeneric:
            0.140
        // Samsung 系列 - 调大圆角以与边框协调
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote:
            0.11
        case .samsungGalaxyFold, .samsungGalaxyFlip:
            0.08
        // Google Pixel 系列
        case .googlePixel, .googlePixelPro, .googlePixelA:
            0.11
        case .googlePixelFold:
            0.08
        // 小米系列
        case .xiaomiMi, .xiaomiUltra, .xiaomiMix, .redmi, .redmiNote, .redmiK, .poco:
            0.11
        // 一加系列
        case .oneplus, .oneplusAce, .oneplusNord:
            0.11
        // OPPO 系列
        case .oppoFind, .oppoFindX, .oppoReno, .oppoA:
            0.11
        // Vivo 系列
        case .vivoX, .vivoS, .vivoY, .iqoo, .iqooNeo:
            0.11
        case .vivoXFold:
            0.08
        // 华为/荣耀系列
        case .huaweiP, .huaweiMate, .huaweiNova, .honor, .honorMagic, .honorX:
            0.11
        case .huaweiMateX:
            0.08
        // Realme 系列
        case .realmeGT, .realme:
            0.11
        // Sony Xperia 系列 - 21:9 屏幕，圆角较小
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            0.08
        // Motorola 系列
        case .motorolaEdge, .motoG:
            0.11
        case .motorolaRazr:
            0.08
        // ASUS 系列
        case .asusROG, .asusZenfone:
            0.10
        // 游戏手机系列 - 圆角较小
        case .nubiaRedMagic, .blackShark, .lenovoLegion:
            0.08
        // 其他品牌
        case .meizu, .nothingPhone, .tcl, .zte, .transsion:
            0.10
        case .androidGeneric:
            0.10
        case .unknown:
            0.10
        }
    }

    /// 默认屏幕内容区域的宽高比 (宽度 / 高度)
    /// 这是用于 DeviceBezelView 的主要参数，确保屏幕区域与视频宽高比一致
    /// 数据来源: screensizes.app
    var defaultScreenAspectRatio: CGFloat {
        defaultAspectRatio
    }

    /// 默认宽高比 (宽度 / 高度)
    /// 数据来源: screensizes.app
    var defaultAspectRatio: CGFloat {
        switch self {
        // iPhone 17 Pro Max - 6.9" (2868×1320)
        case .iPhone17Pro:
            1320.0 / 2868.0
        // iPhone 17 - 6.3" (2622×1206)
        case .iPhone17:
            1206.0 / 2622.0
        // iPhone Air - 6.6" (2740×1280)
        case .iPhoneAir:
            1280.0 / 2740.0
        // iPhone 16 Pro Max - 6.9" (2868×1320)
        case .iPhone16Pro:
            1320.0 / 2868.0
        // iPhone 16 Plus - 6.7" (2796×1290)
        case .iPhone16:
            1290.0 / 2796.0
        // iPhone 16e - 6.1" (2532×1170)
        case .iPhone16e:
            1170.0 / 2532.0
        // iPhone 15 Pro Max
        case .iPhone15Pro:
            1290.0 / 2796.0
        // iPhone 15 Plus
        case .iPhone15:
            1290.0 / 2796.0
        // iPhone 14 Pro Max
        case .iPhone14Pro:
            1290.0 / 2796.0
        // iPhone 14 Plus
        case .iPhone14:
            1284.0 / 2778.0
        // iPhone 13 Pro Max
        case .iPhone13Pro:
            1284.0 / 2778.0
        // iPhone 13
        case .iPhone13:
            1170.0 / 2532.0
        // iPhone 12 Pro Max
        case .iPhone12:
            1284.0 / 2778.0
        // iPhone 11 Pro Max
        case .iPhone11:
            1242.0 / 2688.0
        // iPhone XS Max
        case .iPhoneX:
            1242.0 / 2688.0
        // iPhone SE
        case .iPhoneSE:
            750.0 / 1334.0
        // iPhone 8 Plus
        case .iPhoneLegacy:
            1080.0 / 1920.0
        // iPhone 通用
        case .iPhoneGeneric:
            1290.0 / 2796.0
        // Samsung 系列 - 19.5:9 或 20:9
        case .samsungGalaxyS, .samsungGalaxySUltra:
            1080.0 / 2340.0 // 19.5:9
        case .samsungGalaxyA, .samsungGalaxyNote:
            1080.0 / 2400.0 // 20:9
        case .samsungGalaxyFold:
            1812.0 / 2176.0 // 展开态接近正方形
        case .samsungGalaxyFlip:
            1080.0 / 2640.0 // 22:9 窄长屏
        // Google Pixel 系列 - 20:9
        case .googlePixel, .googlePixelPro, .googlePixelA:
            1080.0 / 2400.0
        case .googlePixelFold:
            1840.0 / 2208.0 // 展开态
        // 小米系列 - 20:9
        case .xiaomiMi, .xiaomiUltra, .xiaomiMix:
            1080.0 / 2400.0
        case .redmi, .redmiNote:
            1080.0 / 2400.0
        case .redmiK, .poco:
            1220.0 / 2712.0 // 部分机型使用 1.5K 屏
        // 一加系列 - 20:9
        case .oneplus, .oneplusAce:
            1080.0 / 2400.0
        case .oneplusNord:
            1080.0 / 2400.0
        // OPPO 系列 - 20:9
        case .oppoFind, .oppoFindX:
            1080.0 / 2412.0
        case .oppoReno, .oppoA:
            1080.0 / 2400.0
        // Vivo 系列 - 20:9
        case .vivoX, .vivoS:
            1080.0 / 2400.0
        case .vivoXFold:
            1916.0 / 2160.0 // 展开态
        case .vivoY:
            1080.0 / 2408.0
        case .iqoo, .iqooNeo:
            1080.0 / 2400.0
        // 华为/荣耀系列 - 20:9
        case .huaweiP, .huaweiMate:
            1080.0 / 2376.0
        case .huaweiMateX:
            1848.0 / 2200.0 // 展开态
        case .huaweiNova:
            1080.0 / 2400.0
        case .honor, .honorMagic:
            1080.0 / 2400.0
        case .honorX:
            1080.0 / 2388.0
        // Realme 系列 - 20:9
        case .realmeGT, .realme:
            1080.0 / 2400.0
        // Sony Xperia 系列 - 21:9 带状屏
        case .sonyXperia1:
            1644.0 / 3840.0 // 21:9 4K
        case .sonyXperia5:
            1080.0 / 2520.0 // 21:9
        case .sonyXperia10:
            1080.0 / 2520.0 // 21:9
        // Motorola 系列 - 20:9 或 22:9
        case .motorolaEdge:
            1080.0 / 2400.0
        case .motorolaRazr:
            1080.0 / 2640.0 // 22:9 翻盖
        case .motoG:
            1080.0 / 2400.0
        // ASUS 系列 - 20:9
        case .asusROG:
            1080.0 / 2448.0 // 游戏屏
        case .asusZenfone:
            1080.0 / 2400.0
        // 游戏手机系列 - 20:9 或更长
        case .nubiaRedMagic:
            1116.0 / 2480.0
        case .blackShark:
            1080.0 / 2400.0
        case .lenovoLegion:
            1080.0 / 2460.0
        // 其他品牌 - 20:9
        case .meizu:
            1080.0 / 2360.0
        case .nothingPhone:
            1080.0 / 2412.0
        case .tcl:
            1080.0 / 2400.0
        case .zte:
            1080.0 / 2400.0
        case .transsion:
            1080.0 / 2400.0
        case .androidGeneric:
            1080.0 / 2400.0
        case .unknown:
            9.0 / 19.0
        }
    }
}

// MARK: - 边框参数

extension DeviceModel {
    /// 金属外壳边框宽度比例（相对于设备宽度）
    /// 金属边框是设备最外层的金属/钛金属框架的可视厚度
    ///
    /// 真实 iPhone 金属边框可视部分很薄，约 0.3-0.5mm
    /// 设备宽约 72mm，比例 ≈ 0.4 / 72 ≈ 0.006
    var metalFrameWidthRatio: CGFloat {
        switch self {
        // iPhone 17 Pro - 钛金属边框
        case .iPhone17Pro:
            0.006
        // iPhone 17 - 铝金属边框
        case .iPhone17:
            0.007
        // iPhone Air - 超薄设计，预计边框更薄
        case .iPhoneAir:
            0.006
        // iPhone 16 Pro - 钛金属边框
        case .iPhone16Pro:
            0.006
        // iPhone 16 - 铝金属边框
        case .iPhone16:
            0.007
        // iPhone 16e - 铝金属边框
        case .iPhone16e:
            0.008
        // iPhone 15 Pro - 钛金属边框
        case .iPhone15Pro:
            0.006
        // iPhone 15 - 铝金属边框
        case .iPhone15:
            0.007
        // iPhone 14 Pro - 不锈钢边框
        case .iPhone14Pro:
            0.007
        // iPhone 14 - 铝金属边框
        case .iPhone14:
            0.008
        // iPhone 13 系列
        case .iPhone13, .iPhone13Pro:
            0.008
        // iPhone 12 系列 - 直角边框设计
        case .iPhone12:
            0.008
        // iPhone 11 系列 - 圆润边框
        case .iPhone11:
            0.010
        // iPhone X/XS/XR
        case .iPhoneX:
            0.012
        // iPhone SE - 较厚边框
        case .iPhoneSE:
            0.015
        // iPhone Legacy
        case .iPhoneLegacy:
            0.015
        // iPhone 通用
        case .iPhoneGeneric:
            0.007
        // Samsung 系列
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote:
            0.006
        case .samsungGalaxyFold, .samsungGalaxyFlip:
            0.005
        // Google Pixel 系列
        case .googlePixel, .googlePixelPro, .googlePixelA:
            0.006
        case .googlePixelFold:
            0.005
        // 小米系列
        case .xiaomiMi, .xiaomiUltra, .xiaomiMix:
            0.006
        case .redmi, .redmiNote, .redmiK, .poco:
            0.007
        // 一加系列
        case .oneplus, .oneplusAce, .oneplusNord:
            0.006
        // OPPO 系列
        case .oppoFind, .oppoFindX, .oppoReno, .oppoA:
            0.006
        // Vivo 系列
        case .vivoX, .vivoS, .vivoY, .iqoo, .iqooNeo:
            0.006
        case .vivoXFold:
            0.005
        // 华为/荣耀系列
        case .huaweiP, .huaweiMate, .huaweiNova:
            0.006
        case .huaweiMateX:
            0.005
        case .honor, .honorMagic, .honorX:
            0.006
        // Realme 系列
        case .realmeGT, .realme:
            0.007
        // Sony 系列
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            0.005
        // Motorola 系列
        case .motorolaEdge, .motoG:
            0.007
        case .motorolaRazr:
            0.005
        // ASUS 系列
        case .asusROG, .asusZenfone:
            0.006
        // 游戏手机系列
        case .nubiaRedMagic, .blackShark, .lenovoLegion:
            0.005
        // 其他品牌
        case .meizu, .nothingPhone, .tcl, .zte, .transsion:
            0.007
        case .androidGeneric:
            0.007
        case .unknown:
            0.007
        }
    }

    /// 屏幕黑边框宽度比例（相对于设备宽度）
    /// 屏幕黑边框是金属边框内侧、屏幕显示区域外侧的黑色边框
    /// 数据来源: 实测数据, screensizes.app
    ///
    /// | 设备 | 黑边框 (mm) | 设备宽 (mm) | 比例 |
    /// |-----|------------|-----------|------|
    /// | iPhone 16 Pro | 1.15 | 71.5 | 0.0161 |
    /// | iPhone 16 | 1.85 | 71.6 | 0.0258 |
    /// | iPhone 15 Pro | 1.55 | 70.6 | 0.0220 |
    /// | iPhone 15 | 1.80 | 71.6 | 0.0251 |
    /// | iPhone 14 Pro | 1.95 | 71.5 | 0.0273 |
    /// | iPhone 14 | 2.39 | 71.5 | 0.0334 |
    /// | iPhone 13 | 2.40 | 71.5 | 0.0336 |
    /// | iPhone 12 | 2.65 | 71.5 | 0.0371 |
    /// | iPhone 11 | 3.50 | 75.7 | 0.0462 |
    /// | iPhone X | 4.00 | 70.9 | 0.0564 |
    /// | iPhone SE | 4.00 | 67.3 | 0.0594 |
    var screenBezelWidthRatio: CGFloat {
        switch self {
        // iPhone 17 Pro - 预计 ~1.0mm (更窄边框)
        case .iPhone17Pro:
            0.014
        // iPhone 17 - 预计与 16 Pro 相近
        case .iPhone17:
            0.016
        // iPhone Air - 超薄设计，边框窄
        case .iPhoneAir:
            0.016
        // iPhone 16 Pro - 1.15mm / 71.5mm (业界最窄边框)
        case .iPhone16Pro:
            0.016
        // iPhone 16 - 1.85mm / 71.6mm
        case .iPhone16:
            0.026
        // iPhone 16e - 类似 iPhone 14 的边框
        case .iPhone16e:
            0.033
        // iPhone 15 Pro - 1.55mm / 70.6mm
        case .iPhone15Pro:
            0.022
        // iPhone 15 - 1.80mm / 71.6mm
        case .iPhone15:
            0.025
        // iPhone 14 Pro - 1.95mm / 71.5mm
        case .iPhone14Pro:
            0.027
        // iPhone 14 - 2.39mm / 71.5mm
        case .iPhone14:
            0.033
        // iPhone 13 系列 - 2.40mm / 71.5mm
        case .iPhone13, .iPhone13Pro:
            0.034
        // iPhone 12 系列 - 2.65mm / 71.5mm
        case .iPhone12:
            0.037
        // iPhone 11 系列 - 3.50mm / 75.7mm
        case .iPhone11:
            0.046
        // iPhone X/XS/XR - 4.00mm / 70.9mm
        case .iPhoneX:
            0.056
        // iPhone SE - 4.00mm / 67.3mm (左右), 顶部底部更宽
        case .iPhoneSE:
            0.059
        // iPhone Legacy
        case .iPhoneLegacy:
            0.059
        // iPhone 通用 - 使用 15 系列参数
        case .iPhoneGeneric:
            0.025
        // Samsung 系列
        case .samsungGalaxyS, .samsungGalaxySUltra:
            0.018
        case .samsungGalaxyA, .samsungGalaxyNote:
            0.022
        case .samsungGalaxyFold, .samsungGalaxyFlip:
            0.015
        // Google Pixel 系列
        case .googlePixel, .googlePixelPro:
            0.020
        case .googlePixelA:
            0.024
        case .googlePixelFold:
            0.015
        // 小米系列
        case .xiaomiMi, .xiaomiUltra:
            0.018
        case .xiaomiMix:
            0.015
        case .redmi, .redmiNote:
            0.025
        case .redmiK, .poco:
            0.020
        // 一加系列
        case .oneplus, .oneplusAce:
            0.018
        case .oneplusNord:
            0.022
        // OPPO 系列
        case .oppoFind, .oppoFindX:
            0.018
        case .oppoReno:
            0.020
        case .oppoA:
            0.025
        // Vivo 系列
        case .vivoX:
            0.018
        case .vivoXFold:
            0.015
        case .vivoS, .vivoY:
            0.022
        case .iqoo, .iqooNeo:
            0.020
        // 华为/荣耀系列
        case .huaweiP, .huaweiMate:
            0.018
        case .huaweiMateX:
            0.015
        case .huaweiNova:
            0.022
        case .honor, .honorMagic:
            0.020
        case .honorX:
            0.024
        // Realme 系列
        case .realmeGT:
            0.020
        case .realme:
            0.024
        // Sony 系列 - 较窄边框
        case .sonyXperia1, .sonyXperia5:
            0.016
        case .sonyXperia10:
            0.020
        // Motorola 系列
        case .motorolaEdge:
            0.020
        case .motorolaRazr:
            0.015
        case .motoG:
            0.025
        // ASUS 系列
        case .asusROG:
            0.018
        case .asusZenfone:
            0.020
        // 游戏手机系列 - 较窄边框
        case .nubiaRedMagic, .blackShark, .lenovoLegion:
            0.016
        // 其他品牌
        case .meizu:
            0.020
        case .nothingPhone:
            0.018
        case .tcl, .zte, .transsion:
            0.025
        case .androidGeneric:
            0.022
        case .unknown:
            0.025
        }
    }

    /// 总边框宽度比例（金属边框 + 屏幕黑边框）
    var totalBezelWidthRatio: CGFloat {
        metalFrameWidthRatio + screenBezelWidthRatio
    }

    /// 边框圆角半径比例（相对于设备宽度）
    /// 设备整体圆角略大于屏幕圆角
    var bezelCornerRadiusRatio: CGFloat {
        switch self {
        // iPhone 17 Pro - 预计与 16 Pro 相近
        case .iPhone17Pro:
            0.153
        // iPhone 17 - 预计与 16 Pro 相近
        case .iPhone17:
            0.153
        // iPhone Air - 超薄设计
        case .iPhoneAir:
            0.153
        // iPhone 16 Pro - 设备圆角约 60pt / 393pt
        case .iPhone16Pro:
            0.153
        // iPhone 16 - 设备圆角约 58pt / 393pt
        case .iPhone16:
            0.148
        // iPhone 16e - 类似 iPhone 14
        case .iPhone16e:
            0.138
        // iPhone 15 Pro
        case .iPhone15Pro:
            0.153
        // iPhone 15
        case .iPhone15:
            0.148
        // iPhone 14 Pro
        case .iPhone14Pro:
            0.153
        // iPhone 14
        case .iPhone14:
            0.138
        // iPhone 13 系列
        case .iPhone13, .iPhone13Pro:
            0.138
        // iPhone 12 系列 - 直角边框设计，设备整体有圆角
        case .iPhone12:
            0.138
        // iPhone 11 系列 - 圆润边框
        case .iPhone11:
            0.116
        // iPhone X/XS/XR
        case .iPhoneX:
            0.123
        // iPhone SE - 较小圆角
        case .iPhoneSE:
            0.030
        // iPhone Legacy
        case .iPhoneLegacy:
            0.025
        // iPhone 通用
        case .iPhoneGeneric:
            0.148
        // Samsung 系列
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote:
            0.10
        case .samsungGalaxyFold, .samsungGalaxyFlip:
            0.06
        // Google Pixel 系列
        case .googlePixel, .googlePixelPro, .googlePixelA:
            0.10
        case .googlePixelFold:
            0.06
        // 小米系列
        case .xiaomiMi, .xiaomiUltra, .xiaomiMix, .redmi, .redmiNote, .redmiK, .poco:
            0.10
        // 一加系列
        case .oneplus, .oneplusAce, .oneplusNord:
            0.10
        // OPPO 系列
        case .oppoFind, .oppoFindX, .oppoReno, .oppoA:
            0.10
        // Vivo 系列
        case .vivoX, .vivoS, .vivoY, .iqoo, .iqooNeo:
            0.10
        case .vivoXFold:
            0.06
        // 华为/荣耀系列
        case .huaweiP, .huaweiMate, .huaweiNova, .honor, .honorMagic, .honorX:
            0.10
        case .huaweiMateX:
            0.06
        // Realme 系列
        case .realmeGT, .realme:
            0.10
        // Sony 系列 - 较小圆角
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            0.08
        // Motorola 系列
        case .motorolaEdge, .motoG:
            0.10
        case .motorolaRazr:
            0.06
        // ASUS 系列
        case .asusROG, .asusZenfone:
            0.09
        // 游戏手机系列 - 较小圆角
        case .nubiaRedMagic, .blackShark, .lenovoLegion:
            0.08
        // 其他品牌
        case .meizu, .nothingPhone, .tcl, .zte, .transsion:
            0.09
        case .androidGeneric:
            0.09
        case .unknown:
            0.08
        }
    }

    /// 边框基础颜色
    var bezelBaseColor: NSColor {
        switch self {
        // iPhone 17/16/15 Pro - 钛金属
        case .iPhone17Pro, .iPhone16Pro, .iPhone15Pro:
            NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        // iPhone Air - 轻量设计，铝金属
        case .iPhoneAir:
            NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        // iPhone 14 Pro - 不锈钢
        case .iPhone14Pro:
            NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        // iPhone 标准版 - 铝金属
        case .iPhone17, .iPhone16, .iPhone16e, .iPhone15, .iPhone14, .iPhone13, .iPhone13Pro, .iPhone12, .iPhone11,
             .iPhoneX:
            NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        // iPhone SE / Legacy
        case .iPhoneSE, .iPhoneLegacy:
            NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        // iPhone 通用
        case .iPhoneGeneric:
            NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        // Samsung 系列
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote,
             .samsungGalaxyFold, .samsungGalaxyFlip:
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        // Google Pixel 系列
        case .googlePixel, .googlePixelPro, .googlePixelA, .googlePixelFold:
            NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        // 小米系列
        case .xiaomiMi, .xiaomiUltra, .xiaomiMix, .redmi, .redmiNote, .redmiK, .poco:
            NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        // 一加系列
        case .oneplus, .oneplusAce, .oneplusNord:
            NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        // OPPO 系列
        case .oppoFind, .oppoFindX, .oppoReno, .oppoA:
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        // Vivo 系列
        case .vivoX, .vivoXFold, .vivoS, .vivoY, .iqoo, .iqooNeo:
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        // 华为/荣耀系列
        case .huaweiP, .huaweiMate, .huaweiMateX, .huaweiNova, .honor, .honorMagic, .honorX:
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        // Realme 系列
        case .realmeGT, .realme:
            NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        // Sony 系列
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        // Motorola 系列
        case .motorolaEdge, .motorolaRazr, .motoG:
            NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        // ASUS 系列
        case .asusROG:
            NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        case .asusZenfone:
            NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        // 游戏手机系列
        case .nubiaRedMagic:
            NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        case .blackShark:
            NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)
        case .lenovoLegion:
            NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
        // 其他品牌
        case .meizu:
            NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        case .nothingPhone:
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        case .tcl, .zte, .transsion:
            NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        case .androidGeneric:
            NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        case .unknown:
            NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0)
        }
    }

    /// 边框高光颜色
    var bezelHighlightColor: NSColor {
        switch self {
        case .iPhone17Pro, .iPhone16Pro, .iPhone15Pro:
            NSColor(white: 0.32, alpha: 1.0) // 钛金属高光
        case .iPhone14Pro:
            NSColor(white: 0.35, alpha: 1.0) // 不锈钢高光
        default:
            NSColor(white: 0.28, alpha: 1.0)
        }
    }
}

// MARK: - 顶部特征

extension DeviceModel {
    /// 顶部特征类型
    enum TopFeature {
        case none
        /// 动态岛 - widthRatio 相对于屏幕宽度，heightRatio 相对于屏幕宽度
        case dynamicIsland(widthRatio: CGFloat, heightRatio: CGFloat)
        /// 刘海 - widthRatio 相对于屏幕宽度，heightRatio 相对于屏幕宽度
        case notch(widthRatio: CGFloat, heightRatio: CGFloat)
        /// 打孔摄像头
        case punchHole(position: PunchHolePosition, sizeRatio: CGFloat)
        /// Home 键
        case homeButton
    }

    enum PunchHolePosition {
        case center
        case topLeft
        case topRight
    }

    /// 顶部特征配置
    /// 动态岛和刘海的尺寸按真实设备比例
    ///
    /// **动态岛尺寸** (iPhone 14 Pro+):
    /// - 宽度: 126pt / 393pt = 0.321
    /// - 高度: 36pt (药丸形状)
    ///
    /// **刘海尺寸**:
    /// | 设备 | 宽度 (pt) | 屏幕宽 (pt) | 比例 | 高度 (pt) |
    /// |-----|----------|-----------|------|----------|
    /// | iPhone 14/13 | 162 | 390 | 0.415 | 34 |
    /// | iPhone 12 | 209 | 390 | 0.536 | 32 |
    /// | iPhone 11/X | 209 | 375-414 | 0.50-0.56 | 30 |
    var topFeature: TopFeature {
        switch self {
        // iPhone 17 Pro - 动态岛 (126pt×36pt / 393pt, 距顶部12.5pt)
        case .iPhone17Pro:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 17 - 动态岛
        case .iPhone17:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone Air - 动态岛
        case .iPhoneAir:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 16 Pro - 动态岛 126pt×36pt / 393pt
        case .iPhone16Pro:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 16 - 动态岛
        case .iPhone16:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 15 Pro - 动态岛
        case .iPhone15Pro:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 15 - 动态岛
        case .iPhone15:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 14 Pro - 首款动态岛
        case .iPhone14Pro:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // iPhone 16e - 刘海 (类似 iPhone 14)
        case .iPhone16e:
            .notch(widthRatio: 0.415, heightRatio: 0.087)
        // iPhone 14 - 小刘海 162pt×34pt / 390pt
        case .iPhone14:
            .notch(widthRatio: 0.415, heightRatio: 0.087)
        // iPhone 13 系列 - 小刘海 (比 12 系列小 20%)
        case .iPhone13, .iPhone13Pro:
            .notch(widthRatio: 0.415, heightRatio: 0.087)
        // iPhone 12 系列 - 中刘海 209pt×32pt / 390pt
        case .iPhone12:
            .notch(widthRatio: 0.536, heightRatio: 0.082)
        // iPhone 11 系列 - 大刘海 209pt×30pt / 414pt
        case .iPhone11:
            .notch(widthRatio: 0.505, heightRatio: 0.072)
        // iPhone X/XS/XR - 大刘海 209pt×30pt / 375pt
        case .iPhoneX:
            .notch(widthRatio: 0.557, heightRatio: 0.080)
        // iPhone SE / Legacy - Home 键
        case .iPhoneSE, .iPhoneLegacy:
            .homeButton
        // iPhone 通用 - 使用动态岛
        case .iPhoneGeneric:
            .dynamicIsland(widthRatio: 0.321, heightRatio: 0.091)
        // Samsung 系列 - 居中打孔
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .samsungGalaxyFold:
            .punchHole(position: .topRight, sizeRatio: 0.032)
        case .samsungGalaxyFlip:
            .punchHole(position: .center, sizeRatio: 0.035)
        // Google Pixel 系列 - 居中打孔
        case .googlePixel, .googlePixelPro, .googlePixelA:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .googlePixelFold:
            .punchHole(position: .topRight, sizeRatio: 0.032)
        // 小米系列 - 居中或左上打孔
        case .xiaomiMi, .xiaomiUltra:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .xiaomiMix:
            .none // MIX 系列部分机型无打孔
        case .redmi, .redmiNote:
            .punchHole(position: .center, sizeRatio: 0.040)
        case .redmiK, .poco:
            .punchHole(position: .center, sizeRatio: 0.038)
        // 一加系列 - 居中打孔
        case .oneplus, .oneplusAce:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .oneplusNord:
            .punchHole(position: .center, sizeRatio: 0.038)
        // OPPO 系列 - 左上打孔
        case .oppoFind, .oppoFindX:
            .punchHole(position: .topLeft, sizeRatio: 0.035)
        case .oppoReno:
            .punchHole(position: .topLeft, sizeRatio: 0.038)
        case .oppoA:
            .punchHole(position: .center, sizeRatio: 0.038)
        // Vivo 系列 - 居中打孔
        case .vivoX:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .vivoXFold:
            .punchHole(position: .topRight, sizeRatio: 0.032)
        case .vivoS, .vivoY:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .iqoo, .iqooNeo:
            .punchHole(position: .center, sizeRatio: 0.038)
        // 华为/荣耀系列 - 居中或左上打孔
        case .huaweiP:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .huaweiMate:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .huaweiMateX:
            .punchHole(position: .topRight, sizeRatio: 0.032)
        case .huaweiNova:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .honor, .honorMagic:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .honorX:
            .punchHole(position: .center, sizeRatio: 0.038)
        // Realme 系列 - 左上打孔
        case .realmeGT:
            .punchHole(position: .topLeft, sizeRatio: 0.035)
        case .realme:
            .punchHole(position: .topLeft, sizeRatio: 0.038)
        // Sony Xperia 系列 - 无打孔（超窄边框设计）
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            .none
        // Motorola 系列 - 居中打孔
        case .motorolaEdge:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .motorolaRazr:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .motoG:
            .punchHole(position: .center, sizeRatio: 0.040)
        // ASUS 系列 - 居中打孔
        case .asusROG:
            .none // ROG Phone 部分机型无打孔
        case .asusZenfone:
            .punchHole(position: .center, sizeRatio: 0.035)
        // 游戏手机系列 - 无打孔或居中打孔
        case .nubiaRedMagic:
            .none // 屏下摄像头
        case .blackShark:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .lenovoLegion:
            .punchHole(position: .center, sizeRatio: 0.035)
        // 其他品牌
        case .meizu:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .nothingPhone:
            .punchHole(position: .topLeft, sizeRatio: 0.035)
        case .tcl, .zte:
            .punchHole(position: .center, sizeRatio: 0.038)
        case .transsion:
            .punchHole(position: .center, sizeRatio: 0.040)
        case .androidGeneric:
            .punchHole(position: .center, sizeRatio: 0.035)
        case .unknown:
            .none
        }
    }
}

// MARK: - 侧边按钮

extension DeviceModel {
    /// 侧边按钮布局
    struct SideButtons {
        let left: [ButtonSpec]
        let right: [ButtonSpec]

        struct ButtonSpec {
            let type: ButtonType
            let topRatio: CGFloat
            let heightRatio: CGFloat
            let width: CGFloat

            enum ButtonType {
                case silentSwitch
                case actionButton // iPhone 15 Pro+ 的操作按钮
                case cameraControl // iPhone 16 Pro 的相机控制按钮
                case volumeUp
                case volumeDown
                case power
            }
        }
    }

    /// 按钮颜色
    var buttonColor: NSColor {
        switch self {
        case .iPhone17Pro, .iPhone16Pro, .iPhone15Pro:
            NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
        default:
            NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
        }
    }

    /// 按钮高光颜色
    var buttonHighlightColor: NSColor {
        NSColor(white: 0.32, alpha: 1.0)
    }

    /// 侧边按钮布局
    /// 位置参数基于真实设备测量数据，参考 iPhone 17 Pro SVG 矢量图
    /// - topRatio: 按钮顶部距离设备顶部的比例
    /// - heightRatio: 按钮高度占设备高度的比例
    ///
    /// iPhone 17 Pro 参考数据 (设备高度 150mm):
    /// - Action Button: y=30.69mm, h=6.97mm → top=0.205, height=0.046
    /// - Volume Up: y=42.77mm, h=11.24mm → top=0.285, height=0.075
    /// - Volume Down: y=57.00mm, h=11.24mm → top=0.380, height=0.075
    /// - Power: y=46.58mm, h=17.66mm → top=0.311, height=0.118
    ///
    /// 注意: Camera Control 按钮在正面视觉上不可见，不绘制
    var sideButtons: SideButtons {
        switch self {
        // iPhone 17 Pro - 操作按钮 + 音量按钮（基于 SVG 精确测量）
        case .iPhone17Pro:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone 17 - 操作按钮 + 音量按钮（与 17 Pro 相同布局）
        case .iPhone17:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone 16 Pro - 操作按钮 + 音量按钮（与 17 Pro 相似布局）
        case .iPhone16Pro:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone 16 标准版 - 操作按钮 + 音量按钮
        case .iPhone16:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone Air - 超薄设计，操作按钮 + 音量按钮
        case .iPhoneAir:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone 16e - 静音开关 + 音量按钮（类似 iPhone 14）
        case .iPhone16e:
            SideButtons(
                left: [
                    .init(type: .silentSwitch, topRatio: 0.195, heightRatio: 0.030, width: 3),
                    .init(type: .volumeUp, topRatio: 0.270, heightRatio: 0.070, width: 3),
                    .init(type: .volumeDown, topRatio: 0.360, heightRatio: 0.070, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.300, heightRatio: 0.110, width: 3),
                ]
            )
        // iPhone 15 Pro - 操作按钮替代静音开关
        case .iPhone15Pro:
            SideButtons(
                left: [
                    .init(type: .actionButton, topRatio: 0.205, heightRatio: 0.046, width: 3),
                    .init(type: .volumeUp, topRatio: 0.285, heightRatio: 0.075, width: 3),
                    .init(type: .volumeDown, topRatio: 0.380, heightRatio: 0.075, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.311, heightRatio: 0.118, width: 3),
                ]
            )
        // iPhone 15/14 Pro/14/13/12 - 静音开关 + 音量按钮
        case .iPhone15, .iPhone14Pro, .iPhone14, .iPhone13, .iPhone13Pro, .iPhone12:
            SideButtons(
                left: [
                    .init(type: .silentSwitch, topRatio: 0.195, heightRatio: 0.030, width: 3),
                    .init(type: .volumeUp, topRatio: 0.270, heightRatio: 0.070, width: 3),
                    .init(type: .volumeDown, topRatio: 0.360, heightRatio: 0.070, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.300, heightRatio: 0.110, width: 3),
                ]
            )
        // iPhone 11/X 系列 - 按钮位置稍有不同
        case .iPhone11, .iPhoneX:
            SideButtons(
                left: [
                    .init(type: .silentSwitch, topRatio: 0.175, heightRatio: 0.028, width: 3),
                    .init(type: .volumeUp, topRatio: 0.245, heightRatio: 0.065, width: 3),
                    .init(type: .volumeDown, topRatio: 0.330, heightRatio: 0.065, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.280, heightRatio: 0.100, width: 3),
                ]
            )
        // iPhone SE / Legacy - 按钮位置更靠上
        case .iPhoneSE, .iPhoneLegacy:
            SideButtons(
                left: [
                    .init(type: .silentSwitch, topRatio: 0.135, heightRatio: 0.025, width: 3),
                    .init(type: .volumeUp, topRatio: 0.195, heightRatio: 0.055, width: 3),
                    .init(type: .volumeDown, topRatio: 0.270, heightRatio: 0.055, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.135, heightRatio: 0.055, width: 3),
                ]
            )
        // iPhone 通用
        case .iPhoneGeneric:
            SideButtons(
                left: [
                    .init(type: .silentSwitch, topRatio: 0.195, heightRatio: 0.030, width: 3),
                    .init(type: .volumeUp, topRatio: 0.270, heightRatio: 0.070, width: 3),
                    .init(type: .volumeDown, topRatio: 0.360, heightRatio: 0.070, width: 3),
                ],
                right: [
                    .init(type: .power, topRatio: 0.300, heightRatio: 0.110, width: 3),
                ]
            )
        // Android 系列 - 按钮在右侧（标准布局）
        case .samsungGalaxyS, .samsungGalaxySUltra, .samsungGalaxyA, .samsungGalaxyNote,
             .samsungGalaxyFold, .samsungGalaxyFlip,
             .googlePixel, .googlePixelPro, .googlePixelA, .googlePixelFold,
             .xiaomiMi, .xiaomiUltra, .xiaomiMix, .redmi, .redmiNote, .redmiK, .poco,
             .oneplus, .oneplusAce, .oneplusNord,
             .oppoFind, .oppoFindX, .oppoReno, .oppoA,
             .vivoX, .vivoXFold, .vivoS, .vivoY, .iqoo, .iqooNeo,
             .huaweiP, .huaweiMate, .huaweiMateX, .huaweiNova, .honor, .honorMagic, .honorX,
             .realmeGT, .realme,
             .motorolaEdge, .motorolaRazr, .motoG,
             .asusZenfone, .meizu, .nothingPhone, .tcl, .zte, .transsion:
            SideButtons(
                left: [],
                right: [
                    .init(type: .volumeUp, topRatio: 0.250, heightRatio: 0.075, width: 2.5),
                    .init(type: .volumeDown, topRatio: 0.345, heightRatio: 0.075, width: 2.5),
                    .init(type: .power, topRatio: 0.460, heightRatio: 0.050, width: 2.5),
                ]
            )
        // Sony Xperia 系列 - 侧边指纹电源键
        case .sonyXperia1, .sonyXperia5, .sonyXperia10:
            SideButtons(
                left: [],
                right: [
                    .init(type: .volumeUp, topRatio: 0.320, heightRatio: 0.070, width: 2.5),
                    .init(type: .volumeDown, topRatio: 0.410, heightRatio: 0.070, width: 2.5),
                    .init(type: .power, topRatio: 0.530, heightRatio: 0.045, width: 2.5),
                ]
            )
        // 游戏手机系列 - 可能有额外按键
        case .asusROG, .nubiaRedMagic, .blackShark, .lenovoLegion:
            SideButtons(
                left: [],
                right: [
                    .init(type: .volumeUp, topRatio: 0.240, heightRatio: 0.080, width: 2.5),
                    .init(type: .volumeDown, topRatio: 0.340, heightRatio: 0.080, width: 2.5),
                    .init(type: .power, topRatio: 0.450, heightRatio: 0.055, width: 2.5),
                ]
            )
        case .androidGeneric:
            SideButtons(
                left: [],
                right: [
                    .init(type: .volumeUp, topRatio: 0.260, heightRatio: 0.070, width: 2.5),
                    .init(type: .volumeDown, topRatio: 0.350, heightRatio: 0.070, width: 2.5),
                    .init(type: .power, topRatio: 0.460, heightRatio: 0.050, width: 2.5),
                ]
            )
        case .unknown:
            SideButtons(left: [], right: [])
        }
    }
}

// MARK: - 设备信息

extension DeviceModel {
    /// 是否为 iOS 设备
    var isIOS: Bool {
        switch self {
        case .iPhone17Pro, .iPhone17, .iPhone16Pro, .iPhone16, .iPhone15Pro, .iPhone15, .iPhone14Pro, .iPhone14,
             .iPhone13, .iPhone13Pro, .iPhone12, .iPhone11, .iPhoneX,
             .iPhoneSE, .iPhoneLegacy, .iPhoneGeneric:
            true
        default:
            false
        }
    }

    /// 设备显示名称（用于 UI 文案）
    var displayName: String {
        switch self {
        case .iPhone17Pro:
            "iPhone 17 Pro"
        case .iPhone17:
            "iPhone 17"
        case .iPhoneAir:
            "iPhone Air"
        case .iPhone16Pro:
            "iPhone 16 Pro"
        case .iPhone16:
            "iPhone 16"
        case .iPhone16e:
            "iPhone 16e"
        case .iPhone15Pro:
            "iPhone 15 Pro"
        case .iPhone15:
            "iPhone 15"
        case .iPhone14Pro:
            "iPhone 14 Pro"
        case .iPhone14:
            "iPhone 14"
        case .iPhone13Pro:
            "iPhone 13 Pro"
        case .iPhone13:
            "iPhone 13"
        case .iPhone12:
            "iPhone 12"
        case .iPhone11:
            "iPhone 11"
        case .iPhoneX:
            "iPhone X"
        case .iPhoneSE:
            "iPhone SE"
        case .iPhoneLegacy:
            "iPhone"
        case .iPhoneGeneric:
            "iPhone"
        // Samsung 系列
        case .samsungGalaxyS:
            "Samsung Galaxy S"
        case .samsungGalaxySUltra:
            "Samsung Galaxy S Ultra"
        case .samsungGalaxyA:
            "Samsung Galaxy A"
        case .samsungGalaxyNote:
            "Samsung Galaxy Note"
        case .samsungGalaxyFold:
            "Samsung Galaxy Fold"
        case .samsungGalaxyFlip:
            "Samsung Galaxy Flip"
        // Google Pixel 系列
        case .googlePixel:
            "Google Pixel"
        case .googlePixelPro:
            "Google Pixel Pro"
        case .googlePixelFold:
            "Google Pixel Fold"
        case .googlePixelA:
            "Google Pixel a"
        // 小米系列
        case .xiaomiMi:
            "Xiaomi"
        case .xiaomiUltra:
            "Xiaomi Ultra"
        case .xiaomiMix:
            "Xiaomi MIX"
        case .redmi:
            "Redmi"
        case .redmiNote:
            "Redmi Note"
        case .redmiK:
            "Redmi K"
        case .poco:
            "POCO"
        // 一加系列
        case .oneplus:
            "OnePlus"
        case .oneplusAce:
            "OnePlus Ace"
        case .oneplusNord:
            "OnePlus Nord"
        // OPPO 系列
        case .oppoFind:
            "OPPO Find"
        case .oppoFindX:
            "OPPO Find X"
        case .oppoReno:
            "OPPO Reno"
        case .oppoA:
            "OPPO A"
        // Vivo 系列
        case .vivoX:
            "Vivo X"
        case .vivoXFold:
            "Vivo X Fold"
        case .vivoS:
            "Vivo S"
        case .vivoY:
            "Vivo Y"
        case .iqoo:
            "iQOO"
        case .iqooNeo:
            "iQOO Neo"
        // 华为/荣耀系列
        case .huaweiP:
            "Huawei P"
        case .huaweiMate:
            "Huawei Mate"
        case .huaweiMateX:
            "Huawei Mate X"
        case .huaweiNova:
            "Huawei nova"
        case .honor:
            "Honor"
        case .honorMagic:
            "Honor Magic"
        case .honorX:
            "Honor X"
        // Realme 系列
        case .realmeGT:
            "Realme GT"
        case .realme:
            "Realme"
        // Sony 系列
        case .sonyXperia1:
            "Sony Xperia 1"
        case .sonyXperia5:
            "Sony Xperia 5"
        case .sonyXperia10:
            "Sony Xperia 10"
        // Motorola 系列
        case .motorolaEdge:
            "Motorola Edge"
        case .motorolaRazr:
            "Motorola Razr"
        case .motoG:
            "Moto G"
        // ASUS 系列
        case .asusROG:
            "ASUS ROG Phone"
        case .asusZenfone:
            "ASUS Zenfone"
        // 游戏手机系列
        case .nubiaRedMagic:
            "Nubia Red Magic"
        case .blackShark:
            "Black Shark"
        case .lenovoLegion:
            "Lenovo Legion"
        // 其他品牌
        case .meizu:
            "Meizu"
        case .nothingPhone:
            "Nothing Phone"
        case .tcl:
            "TCL"
        case .zte:
            "ZTE"
        case .transsion:
            "Transsion"
        case .androidGeneric:
            "Android"
        case .unknown:
            "Device"
        }
    }
}

// MARK: - 设备识别

extension DeviceModel {
    /// 根据 iOS 设备的 productType（型号标识符）识别设备型号
    /// 这是最精确的识别方式，基于设备硬件标识
    ///
    /// - Parameter productType: iOS 设备型号标识符，如 "iPhone17,1"
    /// - Returns: 对应的 DeviceModel
    ///
    /// 型号标识符参考：
    /// - iPhone 18.x = iPhone 17 系列 (2025)
    /// - iPhone 17.x = iPhone 16 系列 (2024)
    /// - iPhone 16.x = iPhone 15 系列 (2023)
    /// - iPhone 15.x = iPhone 14 系列 (2022)
    /// - iPhone 14.x = iPhone 13 系列 (2021)
    /// - iPhone 13.x = iPhone 12 系列 (2020)
    /// - iPhone 12.x = iPhone 11 系列 (2019)
    /// - iPhone 11.x = iPhone XS/XR 系列 (2018)
    /// - iPhone 10.x = iPhone X/8 系列 (2017)
    static func from(productType: String?) -> DeviceModel {
        guard let type = productType, !type.isEmpty else {
            return .iPhoneGeneric
        }

        // 提取主版本号（如 "iPhone17,1" -> 17）
        let components = type.replacingOccurrences(of: "iPhone", with: "").split(separator: ",")
        guard let majorStr = components.first, let major = Int(majorStr) else {
            // 尝试名称匹配作为 fallback
            return identifyiPhone(from: type.lowercased())
        }

        let minor = components.count > 1 ? Int(components[1]) ?? 0 : 0

        switch major {
        // iPhone 18.x = iPhone 17 系列 (2025) + iPhone Air
        case 18:
            switch minor {
            case 1, 2: // iPhone 17 Pro / Pro Max
                return .iPhone17Pro
            case 3: // iPhone 17
                return .iPhone17
            case 4: // iPhone Air (独立型号)
                return .iPhoneAir
            default:
                return .iPhone17
            }

        // iPhone 17.x = iPhone 16 系列 (2024) + iPhone 16e (2025)
        case 17:
            switch minor {
            case 1, 2: // iPhone 16 Pro / Pro Max
                return .iPhone16Pro
            case 5: // iPhone 16e (刘海屏)
                return .iPhone16e
            default: // iPhone 16 / Plus
                return .iPhone16
            }

        // iPhone 16.x = iPhone 15 系列 (2023)
        case 16:
            switch minor {
            case 1, 2: // iPhone 15 Pro / Pro Max
                return .iPhone15Pro
            default: // iPhone 15 / Plus
                return .iPhone15
            }

        // iPhone 15.x = iPhone 14 Pro 系列 (2022) + iPhone 15 标准版 (2023)
        case 15:
            switch minor {
            case 2, 3: // iPhone 14 Pro / Pro Max
                return .iPhone14Pro
            case 4, 5: // iPhone 15 / Plus (动态岛)
                return .iPhone15
            default:
                return .iPhone15
            }

        // iPhone 14.x = iPhone 13 系列 (2021) + iPhone SE 3 + iPhone 14 标准版
        case 14:
            switch minor {
            case 2, 3: // iPhone 13 Pro / Pro Max
                return .iPhone13Pro
            case 4, 5: // iPhone 13 mini / iPhone 13
                return .iPhone13
            case 6: // iPhone SE (3rd gen)
                return .iPhoneSE
            case 7, 8: // iPhone 14 / Plus (特殊：使用 iPhone14,x 标识)
                return .iPhone14
            default:
                return .iPhone13
            }

        // iPhone 13.x = iPhone 12 系列 (2020)
        case 13:
            switch minor {
            case 3, 4: // iPhone 12 Pro / Pro Max
                return .iPhone12
            default: // iPhone 12 mini / iPhone 12
                return .iPhone12
            }

        // iPhone 12.x = iPhone 11 系列 (2019) + iPhone SE 2
        case 12:
            switch minor {
            case 8: // iPhone SE (2nd gen)
                return .iPhoneSE
            default: // iPhone 11 / Pro / Pro Max
                return .iPhone11
            }

        // iPhone 11.x = iPhone XS/XR 系列 (2018)
        case 11:
            return .iPhoneX

        // iPhone 10.x = iPhone X/8 系列 (2017)
        case 10:
            switch minor {
            case 3, 6: // iPhone X
                return .iPhoneX
            default: // iPhone 8 / 8 Plus
                return .iPhoneLegacy
            }

        // 更早的设备
        default:
            if major >= 9 {
                return .iPhoneLegacy
            }
            return .iPhoneGeneric
        }
    }

    /// 根据设备名称识别设备型号（fallback 方式）
    /// - Parameters:
    ///   - deviceName: 设备名称
    ///   - platform: 设备平台
    /// - Returns: 对应的 DeviceModel
    static func identify(from deviceName: String?, platform: DevicePlatform) -> DeviceModel {
        guard let name = deviceName?.lowercased() else {
            return platform == .ios ? .iPhoneGeneric : .androidGeneric
        }

        if platform == .ios {
            return identifyiPhone(from: name)
        } else {
            return identifyAndroid(from: name)
        }
    }

    private static func identifyiPhone(from name: String) -> DeviceModel {
        // iPhone Air (独立型号，需优先判断)
        if name.contains("iphone air") || name.contains("iphoneair") {
            return .iPhoneAir
        }

        // iPhone 17 系列
        if name.contains("iphone 17") || name.contains("iphone17") {
            if name.contains("pro") {
                return .iPhone17Pro
            }
            return .iPhone17
        }

        // iPhone 16e (刘海屏，需优先于 iPhone 16 判断)
        if name.contains("iphone 16e") || name.contains("iphone16e") {
            return .iPhone16e
        }

        // iPhone 16 系列
        if name.contains("iphone 16") || name.contains("iphone16") {
            if name.contains("pro") {
                return .iPhone16Pro
            }
            return .iPhone16
        }

        // iPhone 15 系列
        if name.contains("iphone 15") || name.contains("iphone15") {
            if name.contains("pro") {
                return .iPhone15Pro
            }
            return .iPhone15
        }

        // iPhone 14 系列
        if name.contains("iphone 14") || name.contains("iphone14") {
            if name.contains("pro") {
                return .iPhone14Pro
            }
            return .iPhone14
        }

        // iPhone 13 系列
        if name.contains("iphone 13") || name.contains("iphone13") {
            if name.contains("pro") {
                return .iPhone13Pro
            }
            return .iPhone13
        }

        // iPhone 12 系列
        if name.contains("iphone 12") || name.contains("iphone12") {
            return .iPhone12
        }

        // iPhone 11 系列
        if name.contains("iphone 11") || name.contains("iphone11") {
            return .iPhone11
        }

        // iPhone X 系列
        if name.contains("iphone x") || name.contains("iphone xs") || name.contains("iphone xr") {
            return .iPhoneX
        }

        // iPhone SE
        if name.contains("iphone se") {
            return .iPhoneSE
        }

        // iPhone 8 及更早
        if
            name.contains("iphone 8") || name.contains("iphone 7") || name.contains("iphone 6") ||
            name.contains("iphone8") || name.contains("iphone7") || name.contains("iphone6") {
            return .iPhoneLegacy
        }

        return .iPhoneGeneric
    }

    private static func identifyAndroid(from name: String) -> DeviceModel {
        // Samsung: 检查品牌名、Galaxy 系列名、型号前缀（sm- 或 sm_ 或 sm ）
        if
            name.contains("samsung") || name.contains("galaxy") ||
            name.contains("sm-") || name.contains("sm_") || name.hasPrefix("sm ") {
            if name.contains("fold") || name.contains("z fold") {
                return .samsungGalaxyFold
            }
            if name.contains("flip") || name.contains("z flip") {
                return .samsungGalaxyFlip
            }
            if name.contains("ultra") {
                return .samsungGalaxySUltra
            }
            if name.contains("note") {
                return .samsungGalaxyNote
            }
            if name.contains("galaxy a") || name.hasPrefix("a") {
                return .samsungGalaxyA
            }
            return .samsungGalaxyS
        }

        // Google Pixel
        if name.contains("pixel") || name.contains("google") {
            if name.contains("fold") {
                return .googlePixelFold
            }
            if name.contains("pro") {
                return .googlePixelPro
            }
            if name.contains("a"), !name.contains("max") {
                return .googlePixelA
            }
            return .googlePixel
        }

        // 小米系列
        if name.contains("xiaomi") || name.contains("mi ") || name.hasPrefix("mi") {
            if name.contains("ultra") {
                return .xiaomiUltra
            }
            if name.contains("mix") {
                return .xiaomiMix
            }
            return .xiaomiMi
        }
        if name.contains("redmi") {
            if name.contains("note") {
                return .redmiNote
            }
            if name.contains("k") || name.contains("turbo") {
                return .redmiK
            }
            return .redmi
        }
        if name.contains("poco") {
            return .poco
        }

        // 一加系列
        if name.contains("oneplus") || name.contains("one plus") {
            if name.contains("ace") {
                return .oneplusAce
            }
            if name.contains("nord") {
                return .oneplusNord
            }
            return .oneplus
        }

        // OPPO 系列
        if name.contains("oppo") {
            if name.contains("find x") {
                return .oppoFindX
            }
            if name.contains("find") {
                return .oppoFind
            }
            if name.contains("reno") {
                return .oppoReno
            }
            return .oppoA
        }

        // Vivo 系列
        if name.contains("vivo") {
            if name.contains("fold") {
                return .vivoXFold
            }
            if name.contains("x"), !name.contains("max") {
                return .vivoX
            }
            if name.contains("s") {
                return .vivoS
            }
            return .vivoY
        }
        if name.contains("iqoo") {
            if name.contains("neo") {
                return .iqooNeo
            }
            return .iqoo
        }

        // Realme 系列
        if name.contains("realme") {
            if name.contains("gt") {
                return .realmeGT
            }
            return .realme
        }

        // 华为系列
        if name.contains("huawei") {
            if name.contains("mate x") || name.contains("matex") {
                return .huaweiMateX
            }
            if name.contains("mate") {
                return .huaweiMate
            }
            if
                name.contains("p"),
                name.contains("p4") || name.contains("p5") || name.contains("p6") || name.contains("p7") {
                return .huaweiP
            }
            if name.contains("nova") {
                return .huaweiNova
            }
            return .huaweiP
        }

        // 荣耀系列
        if name.contains("honor") {
            if name.contains("magic") {
                return .honorMagic
            }
            if name.contains("x") {
                return .honorX
            }
            return .honor
        }

        // Sony 系列
        if name.contains("sony") || name.contains("xperia") {
            if name.contains("1") || name.contains("pro") {
                return .sonyXperia1
            }
            if name.contains("5") {
                return .sonyXperia5
            }
            return .sonyXperia10
        }

        // Motorola 系列
        if name.contains("motorola") || name.contains("moto") {
            if name.contains("razr") {
                return .motorolaRazr
            }
            if name.contains("edge") {
                return .motorolaEdge
            }
            return .motoG
        }

        // ASUS 系列
        if name.contains("asus") || name.contains("rog") || name.contains("zenfone") {
            if name.contains("rog") {
                return .asusROG
            }
            return .asusZenfone
        }

        // 游戏手机系列
        if name.contains("nubia") || name.contains("red magic") || name.contains("redmagic") {
            return .nubiaRedMagic
        }
        if name.contains("black shark") || name.contains("blackshark") {
            return .blackShark
        }
        if name.contains("legion") {
            return .lenovoLegion
        }

        // 其他品牌
        if name.contains("meizu") {
            return .meizu
        }
        if name.contains("nothing") {
            return .nothingPhone
        }
        if name.contains("tcl") {
            return .tcl
        }
        if name.contains("zte") {
            return .zte
        }
        if name.contains("infinix") || name.contains("tecno") || name.contains("itel") {
            return .transsion
        }

        return .androidGeneric
    }

    /// 根据 Android 设备的品牌和型号精确识别设备型号
    /// 这是更精确的识别方式，基于设备的 brand 属性
    ///
    /// - Parameter brand: 设备品牌（ro.product.brand）
    /// - Parameter model: 设备型号（ro.product.model）
    /// - Parameter marketName: 市场名称（ro.product.marketname）
    /// - Returns: 对应的 DeviceModel
    static func from(brand: String?, model: String?, marketName: String?) -> DeviceModel {
        let modelLower = model?.lowercased() ?? ""
        let marketLower = marketName?.lowercased() ?? ""

        // 优先使用 brand 精确识别
        if let brand = brand?.lowercased(), !brand.isEmpty {
            // Samsung
            if brand.contains("samsung") {
                if modelLower.contains("fold") || marketLower.contains("fold") {
                    return .samsungGalaxyFold
                }
                if modelLower.contains("flip") || marketLower.contains("flip") {
                    return .samsungGalaxyFlip
                }
                if marketLower.contains("ultra") {
                    return .samsungGalaxySUltra
                }
                if marketLower.contains("note") {
                    return .samsungGalaxyNote
                }
                if modelLower.hasPrefix("a") || marketLower.contains("galaxy a") {
                    return .samsungGalaxyA
                }
                return .samsungGalaxyS
            }

            // Google Pixel
            if brand.contains("google") {
                if modelLower.contains("fold") || marketLower.contains("fold") {
                    return .googlePixelFold
                }
                if marketLower.contains("pro") {
                    return .googlePixelPro
                }
                if marketLower.contains("a"), !marketLower.contains("max") {
                    return .googlePixelA
                }
                return .googlePixel
            }

            // 小米系列
            if brand == "xiaomi" {
                if marketLower.contains("ultra") {
                    return .xiaomiUltra
                }
                if marketLower.contains("mix") {
                    return .xiaomiMix
                }
                return .xiaomiMi
            }
            if brand == "redmi" {
                if marketLower.contains("note") {
                    return .redmiNote
                }
                if marketLower.contains("k") || marketLower.contains("turbo") {
                    return .redmiK
                }
                return .redmi
            }
            if brand == "poco" {
                return .poco
            }

            // OnePlus
            if brand.contains("oneplus") {
                if marketLower.contains("ace") {
                    return .oneplusAce
                }
                if marketLower.contains("nord") {
                    return .oneplusNord
                }
                return .oneplus
            }

            // OPPO
            if brand.contains("oppo") {
                if marketLower.contains("find x") {
                    return .oppoFindX
                }
                if marketLower.contains("find") {
                    return .oppoFind
                }
                if marketLower.contains("reno") {
                    return .oppoReno
                }
                return .oppoA
            }

            // Vivo
            if brand.contains("vivo") {
                if marketLower.contains("fold") {
                    return .vivoXFold
                }
                if marketLower.contains("x"), !marketLower.contains("max") {
                    return .vivoX
                }
                if marketLower.contains("s") {
                    return .vivoS
                }
                return .vivoY
            }
            if brand.contains("iqoo") {
                if marketLower.contains("neo") {
                    return .iqooNeo
                }
                return .iqoo
            }

            // Realme
            if brand.contains("realme") {
                if marketLower.contains("gt") {
                    return .realmeGT
                }
                return .realme
            }

            // 华为
            if brand.contains("huawei") {
                if marketLower.contains("mate x") {
                    return .huaweiMateX
                }
                if marketLower.contains("mate") {
                    return .huaweiMate
                }
                if marketLower.contains("nova") {
                    return .huaweiNova
                }
                return .huaweiP
            }

            // 荣耀
            if brand.contains("honor") {
                if marketLower.contains("magic") {
                    return .honorMagic
                }
                if marketLower.contains("x") {
                    return .honorX
                }
                return .honor
            }

            // Sony
            if brand.contains("sony") {
                if marketLower.contains("1") || marketLower.contains("pro") {
                    return .sonyXperia1
                }
                if marketLower.contains("5") {
                    return .sonyXperia5
                }
                return .sonyXperia10
            }

            // Motorola
            if brand.contains("motorola") {
                if marketLower.contains("razr") {
                    return .motorolaRazr
                }
                if marketLower.contains("edge") {
                    return .motorolaEdge
                }
                return .motoG
            }

            // ASUS
            if brand.contains("asus") {
                if marketLower.contains("rog") {
                    return .asusROG
                }
                return .asusZenfone
            }

            // 游戏手机
            if brand.contains("nubia") {
                return .nubiaRedMagic
            }
            if brand.contains("blackshark") || brand.contains("black shark") {
                return .blackShark
            }
            if brand.contains("lenovo") && marketLower.contains("legion") {
                return .lenovoLegion
            }

            // 其他品牌
            if brand.contains("meizu") {
                return .meizu
            }
            if brand.contains("nothing") {
                return .nothingPhone
            }
            if brand.contains("tcl") {
                return .tcl
            }
            if brand.contains("zte") {
                return .zte
            }
            if brand.contains("infinix") || brand.contains("tecno") || brand.contains("itel") {
                return .transsion
            }
        }

        // 如果 brand 不可用，尝试从 marketName 或 model 推断
        let fallbackName = (marketName ?? model ?? "").lowercased()
        if !fallbackName.isEmpty {
            return identifyAndroid(from: fallbackName)
        }

        return .androidGeneric
    }
}
