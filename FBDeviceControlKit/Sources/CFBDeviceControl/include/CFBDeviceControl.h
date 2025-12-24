/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#ifndef CFBDeviceControl_h
#define CFBDeviceControl_h

// MARK: - CFBControlCore (via module dependency)
// Note: CFBControlCore headers are available because CFBDeviceControl depends on CFBControlCore

// MARK: - Commands

#import "FBDeviceActivationCommands.h"
#import "FBDeviceApplicationCommands.h"
#import "FBDeviceCommands.h"
#import "FBDeviceCrashLogCommands.h"
#import "FBDeviceDebuggerCommands.h"
#import "FBDeviceDebugSymbolsCommands.h"
#import "FBDeviceDeveloperDiskImageCommands.h"
#import "FBDeviceDiagnosticInformationCommands.h"
#import "FBDeviceEraseCommands.h"
#import "FBDeviceFileCommands.h"
#import "FBDeviceLifecycleCommands.h"
#import "FBDeviceLocationCommands.h"
#import "FBDeviceLogCommands.h"
#import "FBDevicePowerCommands.h"
#import "FBDeviceProvisioningProfileCommands.h"
#import "FBDeviceRecoveryCommands.h"
#import "FBDeviceScreenshotCommands.h"
#import "FBDeviceSocketForwardingCommands.h"
#import "FBDeviceVideoRecordingCommands.h"
// FBDeviceXCTestCommands excluded - requires XCTestBootstrap dependency

// MARK: - Management

#import "FBAFCConnection.h"
#import "FBAMDefines.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBAMDeviceManager.h"
#import "FBAMDeviceServiceManager.h"
#import "FBAMDServiceConnection.h"
#import "FBAMRestorableDevice.h"
#import "FBAMRestorableDeviceManager.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceDebugServer.h"
#import "FBDeviceManager.h"
#import "FBDeviceSet.h"
#import "FBDeviceStorage.h"
#import "FBInstrumentsClient.h"
#import "FBManagedConfigClient.h"
#import "FBSpringboardServicesClient.h"

// MARK: - Utility

#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceLinkClient.h"

// MARK: - Video

#import "FBDeviceVideo.h"
#import "FBDeviceVideoStream.h"

// MARK: - Bridge

#import "FBDeviceControlBridge.h"

// MARK: - Original Umbrella Header

#import "FBDeviceControl.h"

#endif /* CFBDeviceControl_h */

