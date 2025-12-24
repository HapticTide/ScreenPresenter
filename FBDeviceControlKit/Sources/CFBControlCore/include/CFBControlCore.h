/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#ifndef CFBControlCore_h
#define CFBControlCore_h

// MARK: - Async

#import "FBFuture.h"
#import "FBFuture+Sync.h"
#import "FBFutureContextManager.h"

// MARK: - Applications

#import "FBBinaryDescriptor.h"
#import "FBBundleDescriptor.h"
#import "FBBundleDescriptor+Application.h"
#import "FBInstalledApplication.h"

// MARK: - Codesigning

#import "FBCodesignProvider.h"

// MARK: - Commands

#import "FBAccessibilityCommands.h"
#import "FBApplicationCommands.h"
#import "FBCrashLogCommands.h"
#import "FBDapServerCommands.h"
#import "FBDebuggerCommands.h"
#import "FBDeveloperDiskImageCommands.h"
#import "FBDiagnosticInformationCommands.h"
#import "FBEraseCommands.h"
#import "FBFileCommands.h"
#import "FBFileContainer.h"
#import "FBInstrumentsCommands.h"
#import "FBiOSTargetCommandForwarder.h"
#import "FBLifecycleCommands.h"
#import "FBLocationCommands.h"
#import "FBLogCommands.h"
#import "FBMemoryCommands.h"
#import "FBNotificationCommands.h"
#import "FBPowerCommands.h"
#import "FBProcessSpawnCommands.h"
#import "FBProvisioningProfileCommands.h"
#import "FBScreenshotCommands.h"
#import "FBSettingsCommands.h"
#import "FBVideoRecordingCommands.h"
#import "FBVideoStreamCommands.h"
#import "FBXCTestCommands.h"
#import "FBXCTraceRecordCommands.h"

// MARK: - Configuration

#import "FBApplicationLaunchConfiguration.h"
#import "FBArchitectureProcessAdapter.h"
#import "FBInstrumentsConfiguration.h"
#import "FBiOSTargetConfiguration.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessSpawnConfiguration.h"
#import "FBTestLaunchConfiguration.h"
#import "FBVideoStreamConfiguration.h"
#import "FBXCTestShimConfiguration.h"
#import "FBXCTraceConfiguration.h"

// MARK: - Crashes

#import "FBCrashLog.h"
#import "FBCrashLogNotifier.h"
#import "FBCrashLogParser.h"

// MARK: - Management

#import "FBiOSTarget.h"
#import "FBiOSTargetConstants.h"
#import "FBiOSTargetOperation.h"
#import "FBiOSTargetSet.h"

// MARK: - Processes

#import "FBProcessFetcher.h"
#import "FBProcessInfo.h"
#import "FBProcessTerminationStrategy.h"
#import "FBServiceManagement.h"

// MARK: - Reporting

#import "FBEventReporter.h"
#import "FBEventReporterSubject.h"

// MARK: - Sockets

#import "FBSocketServer.h"

// MARK: - Tasks

#import "FBLaunchedApplication.h"
#import "FBProcess.h"
#import "FBProcessBuilder.h"

// MARK: - Utility

// FBAccessibilityTraits excluded - requires AXRuntime private framework
#import "FBArchitecture.h"
#import "FBArchiveOperations.h"
#import "FBCollectionInformation.h"
#import "FBCollectionOperations.h"
#import "FBConcatedJsonParser.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBControlCoreError.h"
#import "FBControlCoreFrameworkLoader.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBControlCoreLogger+OSLog.h"
#import "FBCrashLogStore.h"
#import "FBDataBuffer.h"
#import "FBDataConsumer.h"
#import "FBDeveloperDiskImage.h"
#import "FBFileReader.h"
#import "FBFileWriter.h"
#import "FBInstrumentsOperation.h"
#import "FBLoggingWrapper.h"
#import "FBProcessIO.h"
#import "FBProcessStream.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"
#import "FBVideoFileWriter.h"
#import "FBVideoStream.h"
#import "FBWeakFramework.h"
#import "FBWeakFramework+ApplePrivateFrameworks.h"
#import "FBXcodeConfiguration.h"
#import "FBXcodeDirectory.h"
#import "FBXCTraceOperation.h"
#import "NSPredicate+FBControlCore.h"

#endif /* CFBControlCore_h */
