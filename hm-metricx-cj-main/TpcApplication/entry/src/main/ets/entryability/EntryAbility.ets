/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
import { AbilityConstant, UIAbility, Want, Ability, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { requireCJLib } from "libark_interop_loader.so";

interface CJAbility {
  ark_UIAbility_createCJAbility(name: string, ability: UIAbility): number

  ark_UIAbility_onCreate(id: number, want: Want, launchParam: AbilityConstant.LaunchParam): void

  ark_UIAbility_onWindowStageCreate(id: number, windowStage: window.WindowStage): void

  ark_UIAbility_onWindowStageWillDestroy(id: number, windowStage: window.WindowStage): void

  ark_UIAbility_onWindowStageDestroy(id: number): void

  ark_UIAbility_onWindowStageRestore(id: number, windowStage: window.WindowStage): void

  ark_UIAbility_onDestroy(id: number): void

  ark_UIAbility_onForeground(id: number): void

  ark_UIAbility_onBackground(id: number): void

  ark_UIAbility_onContinue(id: number, wantParam: Record<string, Object>): AbilityConstant.OnContinueResult

  ark_UIAbility_onNewWant(id: number, want: Want, launchParam: AbilityConstant.LaunchParam): void

  ark_UIAbility_onDump(id: number, params: string[]): string[]

  ark_UIAbility_onSaveState(id: number, reason: AbilityConstant.StateType,
    wantParam: Record<string, Object>): AbilityConstant.OnSaveResult

  ark_UIAbility_onShare(id: number, wantParam: Record<string, Object>): void

  ark_UIAbility_onPrepareToTerminate(id: number): boolean

  ark_UIAbility_onBackPressed(id: number): boolean

  ark_UIAbility_onConfigurationUpdate(id: number, config: Configuration): void

  ark_UIAbility_onMemoryLevel(id: number, level: AbilityConstant.MemoryLevel): void
}

let lib: CJAbility

export default class EntryAbility extends UIAbility {
  cjUIAbilityId: number = 0

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');

    lib = requireCJLib("libtpc.AbilityKit.interop_libs.uiability_interop.so") as CJAbility
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_UIAbility_createCJAbility(this.context.abilityInfo.name, this)
    lib.ark_UIAbility_onCreate(this.cjUIAbilityId, want, launchParam)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    lib.ark_UIAbility_onWindowStageCreate(this.cjUIAbilityId, windowStage)
  }

  onWindowStageWillDestroy(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageWillDestroy');
    lib.ark_UIAbility_onWindowStageWillDestroy(this.cjUIAbilityId, windowStage);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    lib.ark_UIAbility_onWindowStageDestroy(this.cjUIAbilityId);
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageRestore');
    lib.ark_UIAbility_onWindowStageRestore(this.cjUIAbilityId, windowStage);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    lib.ark_UIAbility_onDestroy(this.cjUIAbilityId);
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    lib.ark_UIAbility_onForeground(this.cjUIAbilityId);
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
    lib.ark_UIAbility_onBackground(this.cjUIAbilityId);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onContinue');
    return lib.ark_UIAbility_onContinue(this.cjUIAbilityId, wantParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onNewWant');
    lib.ark_UIAbility_onNewWant(this.cjUIAbilityId, want, launchParam);
  }

  onDump(params: string[]): string[] {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDump');
    return lib.ark_UIAbility_onDump(this.cjUIAbilityId, params);
  }

  onSaveState(reason: AbilityConstant.StateType, wantParam: Record<string, Object>): AbilityConstant.OnSaveResult {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onSaveState');
    return lib.ark_UIAbility_onSaveState(this.cjUIAbilityId, reason, wantParam);
  }

  onShare(wantParam: Record<string, Object>): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onShare');
    lib.ark_UIAbility_onShare(this.cjUIAbilityId, wantParam);
  }

  onPrepareToTerminate(): boolean {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onPrepareToTerminate');
    return lib.ark_UIAbility_onPrepareToTerminate(this.cjUIAbilityId);
  }

  onBackPressed(): boolean {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackPressed');
    return lib.ark_UIAbility_onBackPressed(this.cjUIAbilityId);
  }

  onConfigurationUpdate(config: Configuration) {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onConfigurationUpdate');
    lib.ark_UIAbility_onConfigurationUpdate(this.cjUIAbilityId, config);
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onMemoryLevel');
    lib.ark_UIAbility_onMemoryLevel(this.cjUIAbilityId, level);
  }
}
